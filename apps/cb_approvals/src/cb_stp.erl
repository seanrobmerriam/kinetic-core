%% @doc Straight-Through Processing (STP) evaluation engine.
%%
%% Evaluates a payment order against configurable rules to determine whether
%% it can be automatically processed (straight-through) or requires manual
%% intervention (exception).
%%
%% STP auto-approves if ALL of the following are true:
%% 1. Amount <= STP threshold (default: 100_000 minor units / $1,000.00)
%% 2. Party KYC status = approved
%% 3. Source account status = active
%%
%% Any failure routes to the exception queue with a reason.
-module(cb_stp).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([evaluate/1, stp_threshold/0]).

%% Default STP threshold in minor units ($1,000.00 USD equivalent)
-define(DEFAULT_STP_THRESHOLD, 100_000).

%% @doc Evaluate a payment order for straight-through processing.
-dialyzer({nowarn_function, evaluate/1}).
-spec evaluate(#payment_order{}) ->
    straight_through | {exception, binary()}.
evaluate(Order) ->
    Threshold = stp_threshold(),
    case Order#payment_order.amount > Threshold of
        true ->
            {exception, <<"Amount exceeds STP threshold">>};
        false ->
            check_kyc(Order)
    end.

-dialyzer({nowarn_function, check_kyc/1}).
-spec check_kyc(#payment_order{}) ->
    straight_through | {exception, binary()}.
check_kyc(Order) ->
    case mnesia:dirty_read(party, Order#payment_order.party_id) of
        [] ->
            {exception, <<"Party not found">>};
        [Party] when Party#party.kyc_status =/= approved ->
            {exception, <<"Party KYC not approved">>};
        [_Party] ->
            check_account(Order)
    end.

-dialyzer({nowarn_function, check_account/1}).
-spec check_account(#payment_order{}) ->
    straight_through | {exception, binary()}.
check_account(Order) ->
    case mnesia:dirty_read(account, Order#payment_order.source_account_id) of
        [] ->
            {exception, <<"Source account not found">>};
        [Account] when Account#account.status =/= active ->
            {exception, <<"Source account not active">>};
        [_Account] ->
            straight_through
    end.

%% @doc Get the configured STP threshold in minor units.
-spec stp_threshold() -> pos_integer().
stp_threshold() ->
    application:get_env(cb_approvals, stp_threshold, ?DEFAULT_STP_THRESHOLD).
