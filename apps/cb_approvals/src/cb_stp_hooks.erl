%% @doc STP compliance decision hooks (TASK-051).
%%
%% A hook is a function that inspects a payment order and returns
%% `ok` (pass) or `{halt, Reason}` (block the payment).
%%
%% `run_hooks/1` executes all registered hooks in order and short-circuits
%% on the first halt.  This is the integration point for AML and sanctions
%% screening within the STP evaluation pipeline.
-module(cb_stp_hooks).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    run_hooks/1,
    aml_hook/1,
    sanctions_hook/1
]).

%%% --------------------------------------------------------------- API ----

%% @doc Run all compliance hooks against a payment order.
%%
%% Hooks run in the order defined in `hooks/0`.  Returns `ok` if every
%% hook passes, or `{halt, Reason}` as soon as one fires.
-spec run_hooks(#payment_order{}) -> ok | {halt, binary()}.
run_hooks(Order) ->
    exec_hooks(hooks(), Order).

%% @doc AML screening hook.
%%
%% Delegates to `cb_aml:evaluate_transaction/2`.  Halts if the party is
%% flagged by any active AML rule.
-spec aml_hook(#payment_order{}) -> ok | {halt, binary()}.
aml_hook(Order) ->
    case cb_aml:evaluate_transaction(Order#payment_order.party_id,
                                     Order#payment_order.amount) of
        []    -> ok;
        Flags when is_list(Flags) ->
            {halt, <<"AML flag: transaction flagged for review">>}
    end.

%% @doc Sanctions screening hook.
%%
%% Checks the party's `sanctions_blocked` metadata flag.  If the party
%% is not found, the hook halts to prevent processing against unknown parties.
-spec sanctions_hook(#payment_order{}) -> ok | {halt, binary()}.
sanctions_hook(Order) ->
    case mnesia:dirty_read(party, Order#payment_order.party_id) of
        [] ->
            {halt, <<"Sanctions check: party not found">>};
        [Party] ->
            Meta = case Party#party.metadata of undefined -> #{}; M -> M end,
            case maps:get(sanctions_blocked, Meta, false) of
                true  -> {halt, <<"Sanctions check: party on blocked list">>};
                false -> ok
            end
    end.

%%% ---------------------------------------------------------- INTERNALS ---

%% @private The ordered list of hooks to execute.
-spec hooks() -> [fun((#payment_order{}) -> ok | {halt, binary()})].
hooks() ->
    [
        fun sanctions_hook/1,
        fun aml_hook/1
    ].

-spec exec_hooks([fun((#payment_order{}) -> ok | {halt, binary()})],
                 #payment_order{}) ->
    ok | {halt, binary()}.
exec_hooks([], _Order) ->
    ok;
exec_hooks([Hook | Rest], Order) ->
    case Hook(Order) of
        ok            -> exec_hooks(Rest, Order);
        {halt, _} = H -> H
    end.
