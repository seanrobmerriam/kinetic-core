%% @doc Domestic payment order lifecycle management.
%%
%% A payment order represents a payment instruction with full lifecycle
%% tracking: initiated → validating → processing → completed | failed | cancelled.
%%
%% Cancel is allowed from: initiated, validating.
%% Retry is allowed from: failed.
%% Each new order is evaluated by cb_stp:evaluate/1.
-module(cb_payment_orders).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    initiate/5,
    get_payment/1,
    cancel_payment/1,
    retry_payment/1,
    list_payments_for_party/1
]).

%% @doc Initiate a new domestic payment order.
%%
%% Creates a payment_order record, runs STP evaluation, and if approved
%% straight-through, processes immediately. If exception, queues for review.
%%
%% Idempotent: same idempotency_key returns existing order.
-spec initiate(binary(), uuid(), uuid(), uuid(), amount()) ->
    {ok, #payment_order{}} | {error, atom()}.
initiate(IdempotencyKey, PartyId, SourceAccountId, DestAccountId, Amount) ->
    case find_by_idempotency_key(IdempotencyKey) of
        {ok, Existing} -> {ok, Existing};
        not_found ->
            do_initiate(IdempotencyKey, PartyId, SourceAccountId, DestAccountId, Amount)
    end.

-spec do_initiate(binary(), uuid(), uuid(), uuid(), amount()) ->
    {ok, #payment_order{}} | {error, atom()}.
do_initiate(_IKey, _PartyId, _SourceId, _DestId, Amount) when Amount =< 0 ->
    {error, invalid_amount};
do_initiate(IKey, PartyId, SourceAccountId, DestAccountId, Amount) ->
    case cb_accounts:get_account(SourceAccountId) of
        {error, not_found} -> {error, source_account_not_found};
        {ok, SrcAccount} ->
            case cb_accounts:get_account(DestAccountId) of
                {error, not_found} -> {error, dest_account_not_found};
                {ok, _DestAccount} ->
                    Now = erlang:system_time(millisecond),
                    PaymentId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
                    Order = #payment_order{
                        payment_id        = PaymentId,
                        idempotency_key   = IKey,
                        party_id          = PartyId,
                        source_account_id = SourceAccountId,
                        dest_account_id   = DestAccountId,
                        amount            = Amount,
                        currency          = SrcAccount#account.currency,
                        description       = <<"Domestic payment">>,
                        status            = initiated,
                        stp_decision      = undefined,
                        failure_reason    = undefined,
                        retry_count       = 0,
                        created_at        = Now,
                        updated_at        = Now
                    },
                    F = fun() -> mnesia:write(payment_order, Order, write) end,
                    case mnesia:transaction(F) of
                        {atomic, ok} ->
                            run_stp_and_process(Order);
                        {aborted, Reason} ->
                            {error, Reason}
                    end
            end
    end.

-spec run_stp_and_process(#payment_order{}) -> {ok, #payment_order{}}.
run_stp_and_process(Order) ->
    case cb_stp:evaluate(Order) of
        straight_through ->
            process_payment(Order#payment_order{stp_decision = straight_through});
        {exception, Reason} ->
            queue_exception(Order, Reason)
    end.

-spec process_payment(#payment_order{}) -> {ok, #payment_order{}}.
process_payment(Order) ->
    Now = erlang:system_time(millisecond),
    Processing = Order#payment_order{status = processing, updated_at = Now},
    save_order(Processing),
    Result = cb_payments:transfer(
        Order#payment_order.idempotency_key,
        Order#payment_order.source_account_id,
        Order#payment_order.dest_account_id,
        Order#payment_order.amount,
        Order#payment_order.currency,
        <<"Domestic payment order ", (Order#payment_order.payment_id)/binary>>
    ),
    Now2 = erlang:system_time(millisecond),
    case Result of
        {ok, _Txn} ->
            Completed = Processing#payment_order{
                status     = completed,
                updated_at = Now2
            },
            save_order(Completed),
            {ok, Completed};
        {error, Reason} ->
            ReasonBin = atom_to_binary(Reason, utf8),
            Failed = Processing#payment_order{
                status         = failed,
                failure_reason = ReasonBin,
                updated_at     = Now2
            },
            save_order(Failed),
            {ok, Failed}
    end.

-dialyzer({nowarn_function, queue_exception/2}).
-spec queue_exception(#payment_order{}, binary()) -> {ok, #payment_order{}}.
queue_exception(Order, Reason) ->
    Now = erlang:system_time(millisecond),
    Queued = Order#payment_order{
        status       = validating,
        stp_decision = exception_queued,
        updated_at   = Now
    },
    save_order(Queued),
    _ = cb_exception_queue:enqueue(Order#payment_order.payment_id, Reason),
    {ok, Queued}.

-spec save_order(#payment_order{}) -> ok.
save_order(Order) ->
    F = fun() -> mnesia:write(payment_order, Order, write) end,
    {atomic, ok} = mnesia:transaction(F),
    ok.

%% @doc Get a payment order by ID.
-spec get_payment(uuid()) -> {ok, #payment_order{}} | {error, not_found}.
get_payment(PaymentId) ->
    case mnesia:dirty_read(payment_order, PaymentId) of
        [Order] -> {ok, Order};
        [] -> {error, not_found}
    end.

%% @doc Cancel a payment order (only from initiated or validating state).
-spec cancel_payment(uuid()) ->
    {ok, #payment_order{}} | {error, not_found | cannot_cancel}.
cancel_payment(PaymentId) ->
    Now = erlang:system_time(millisecond),
    F = fun() ->
        case mnesia:read(payment_order, PaymentId, write) of
            [] -> {error, not_found};
            [Order] when Order#payment_order.status =:= initiated;
                         Order#payment_order.status =:= validating ->
                Cancelled = Order#payment_order{status = cancelled, updated_at = Now},
                mnesia:write(payment_order, Cancelled, write),
                {ok, Cancelled};
            [_Order] ->
                {error, cannot_cancel}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, Reason} -> {error, Reason}
    end.

%% @doc Retry a failed payment order.
-spec retry_payment(uuid()) ->
    {ok, #payment_order{}} | {error, not_found | cannot_retry}.
retry_payment(PaymentId) ->
    case get_payment(PaymentId) of
        {error, not_found} -> {error, not_found};
        {ok, Order} when Order#payment_order.status =:= failed ->
            Now = erlang:system_time(millisecond),
            Retrying = Order#payment_order{
                status         = initiated,
                retry_count    = Order#payment_order.retry_count + 1,
                failure_reason = undefined,
                updated_at     = Now
            },
            save_order(Retrying),
            run_stp_and_process(Retrying);
        {ok, _} ->
            {error, cannot_retry}
    end.

%% @doc List all payment orders for a party.
-spec list_payments_for_party(uuid()) -> [#payment_order{}].
list_payments_for_party(PartyId) ->
    mnesia:dirty_index_read(payment_order, PartyId, party_id).

-spec find_by_idempotency_key(binary()) -> {ok, #payment_order{}} | not_found.
find_by_idempotency_key(Key) ->
    case mnesia:dirty_index_read(payment_order, Key, idempotency_key) of
        [Order | _] -> {ok, Order};
        [] -> not_found
    end.
