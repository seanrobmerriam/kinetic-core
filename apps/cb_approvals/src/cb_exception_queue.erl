%% @doc Exception queue for payment orders requiring manual intervention.
%%
%% Payment orders that fail STP evaluation are placed in the exception queue.
%% Operations staff review and either approve or reject each item.
%% Approved items are re-submitted for processing; rejected items are marked cancelled.
-module(cb_exception_queue).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    enqueue/2,
    get_item/1,
    list_pending/0,
    resolve/3
]).

%% @doc Enqueue a payment order for manual review.
-spec enqueue(uuid(), binary()) -> {ok, #exception_item{}} | {error, term()}.
enqueue(PaymentId, Reason) ->
    Now = erlang:system_time(millisecond),
    ItemId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
    Item = #exception_item{
        item_id          = ItemId,
        payment_id       = PaymentId,
        reason           = Reason,
        status           = pending,
        resolution       = undefined,
        resolved_by      = undefined,
        resolution_notes = undefined,
        created_at       = Now,
        updated_at       = Now
    },
    F = fun() -> mnesia:write(exception_item, Item, write) end,
    case mnesia:transaction(F) of
        {atomic, ok} -> {ok, Item};
        {aborted, AbortReason} -> {error, AbortReason}
    end.

%% @doc Get an exception queue item by ID.
-spec get_item(uuid()) -> {ok, #exception_item{}} | {error, not_found}.
get_item(ItemId) ->
    case mnesia:dirty_read(exception_item, ItemId) of
        [Item] -> {ok, Item};
        [] -> {error, not_found}
    end.

%% @doc List all pending exception queue items.
-spec list_pending() -> [#exception_item{}].
list_pending() ->
    mnesia:dirty_index_read(exception_item, pending, status).

%% @doc Resolve an exception item as approved or rejected.
%%
%% On approval: re-submits the payment order for processing.
%% On rejection: marks the payment order as cancelled.
-spec resolve(uuid(), approved | rejected, binary()) ->
    {ok, #exception_item{}} | {error, not_found | already_resolved | invalid_resolution}.
resolve(_ItemId, Resolution, _Notes) when
        Resolution =/= approved, Resolution =/= rejected ->
    {error, invalid_resolution};
resolve(ItemId, Resolution, Notes) ->
    Now = erlang:system_time(millisecond),
    F = fun() ->
        case mnesia:read(exception_item, ItemId, write) of
            [] ->
                {error, not_found};
            [Item] when Item#exception_item.status =/= pending ->
                {error, already_resolved};
            [Item] ->
                Resolved = Item#exception_item{
                    status           = resolved,
                    resolution       = Resolution,
                    resolution_notes = Notes,
                    updated_at       = Now
                },
                mnesia:write(exception_item, Resolved, write),
                {ok, Resolved, Item#exception_item.payment_id}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, {ok, Resolved, PaymentId}} ->
            apply_resolution(Resolution, PaymentId),
            {ok, Resolved};
        {atomic, {error, Reason}} ->
            {error, Reason};
        {aborted, Reason} ->
            {error, Reason}
    end.

-spec apply_resolution(approved | rejected, uuid()) -> ok.
apply_resolution(approved, PaymentId) ->
    case cb_payment_orders:get_payment(PaymentId) of
        {ok, Order} ->
            _ = cb_payment_orders:retry_payment(Order#payment_order.payment_id),
            ok;
        {error, _} ->
            ok
    end;
apply_resolution(rejected, PaymentId) ->
    _ = cb_payment_orders:cancel_payment(PaymentId),
    ok.
