%% @doc Straight-Through Processing (STP) evaluation engine.
%%
%% Evaluation pipeline (in order):
%% 1. Compliance hooks — sanctions + AML screening (cb_stp_hooks)
%% 2. Configurable rule engine — custom routing rules (cb_stp_rules)
%% 3. Legacy hardcoded checks — amount threshold, KYC, account status
%%
%% The pipeline short-circuits: the first non-pass result is returned.
%% This preserves backward compatibility — when no custom rules are configured
%% the legacy checks behave exactly as before.
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
    case cb_stp_hooks:run_hooks(Order) of
        {halt, Reason} ->
            {exception, Reason};
        ok ->
            case cb_stp_rules:evaluate_order(Order) of
                straight_through -> straight_through;
                exception        -> {exception, <<"Matched routing rule: exception">>};
                block            -> {exception, <<"Matched routing rule: block">>};
                no_match         -> legacy_evaluate(Order)
            end
    end.

-spec legacy_evaluate(#payment_order{}) ->
    straight_through | {exception, binary()}.
legacy_evaluate(Order) ->
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
