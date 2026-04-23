%% @doc STP routing rule engine (TASK-050).
%%
%% Stores configurable `#stp_routing_rule{}` records in Mnesia and evaluates
%% a payment order against them in priority order.
%%
%% Rules are tried lowest-priority-number first.  The first rule that matches
%% returns its action (`straight_through | exception | block`).
%% If no rule matches the order continues to the legacy hardcoded checks
%% inside `cb_stp`.
-module(cb_stp_rules).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    create_rule/5,
    get_rule/1,
    list_rules/0,
    update_rule/2,
    delete_rule/1,
    enable_rule/1,
    disable_rule/1,
    evaluate_order/1
]).

%%% ----------------------------------------------------------------- CRUD ---

%% @doc Create a new routing rule.
-spec create_rule(
    binary(),
    pos_integer(),
    condition_type(),
    map(),
    straight_through | exception | block
) -> {ok, #stp_routing_rule{}} | {error, term()}.
create_rule(Name, Priority, ConditionType, Params, Action) ->
    Now = erlang:system_time(millisecond),
    RuleId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
    Rule = #stp_routing_rule{
        rule_id         = RuleId,
        name            = Name,
        priority        = Priority,
        condition_type  = ConditionType,
        condition_params = Params,
        action          = Action,
        enabled         = true,
        created_at      = Now,
        updated_at      = Now
    },
    F = fun() -> mnesia:write(stp_routing_rule, Rule, write) end,
    case mnesia:transaction(F) of
        {atomic, ok}           -> {ok, Rule};
        {aborted, AbortReason} -> {error, AbortReason}
    end.

%% @doc Fetch a rule by ID.
-spec get_rule(uuid()) -> {ok, #stp_routing_rule{}} | {error, not_found}.
get_rule(RuleId) ->
    case mnesia:dirty_read(stp_routing_rule, RuleId) of
        [Rule] -> {ok, Rule};
        []     -> {error, not_found}
    end.

%% @doc List all rules sorted ascending by priority.
-spec list_rules() -> [#stp_routing_rule{}].
list_rules() ->
    Rules = mnesia:dirty_match_object(stp_routing_rule,
                                      #stp_routing_rule{_ = '_'}),
    lists:sort(fun(A, B) ->
        A#stp_routing_rule.priority =< B#stp_routing_rule.priority
    end, Rules).

%% @doc Apply a map of field updates to an existing rule.
%%
%% Accepted keys: name, priority, condition_type, condition_params,
%%                action, enabled.
-spec update_rule(uuid(), map()) ->
    {ok, #stp_routing_rule{}} | {error, not_found | term()}.
update_rule(RuleId, Updates) ->
    Now = erlang:system_time(millisecond),
    F = fun() ->
        case mnesia:read(stp_routing_rule, RuleId, write) of
            []     -> {error, not_found};
            [Rule] ->
                Updated = apply_updates(Rule, Updates, Now),
                mnesia:write(stp_routing_rule, Updated, write),
                {ok, Updated}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result}       -> Result;
        {aborted, AbortReason} -> {error, AbortReason}
    end.

%% @doc Delete a rule permanently.
-spec delete_rule(uuid()) -> ok | {error, not_found}.
delete_rule(RuleId) ->
    F = fun() ->
        case mnesia:read(stp_routing_rule, RuleId, write) of
            []     -> {error, not_found};
            [_]    ->
                mnesia:delete(stp_routing_rule, RuleId, write),
                ok
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result}       -> Result;
        {aborted, AbortReason} -> {error, AbortReason}
    end.

%% @doc Enable a rule.
-spec enable_rule(uuid()) -> {ok, #stp_routing_rule{}} | {error, not_found | term()}.
enable_rule(RuleId) ->
    update_rule(RuleId, #{enabled => true}).

%% @doc Disable a rule (it will be skipped during evaluation).
-spec disable_rule(uuid()) -> {ok, #stp_routing_rule{}} | {error, not_found | term()}.
disable_rule(RuleId) ->
    update_rule(RuleId, #{enabled => false}).

%%% --------------------------------------------------------------- EVAL ---

%% @doc Evaluate an order against all enabled rules in priority order.
%%
%% Returns the action from the first matching rule, or `no_match` if
%% no enabled rule applies.
-spec evaluate_order(#payment_order{}) ->
    straight_through | exception | block | no_match.
evaluate_order(Order) ->
    EnabledRules = [R || R <- list_rules(), R#stp_routing_rule.enabled =:= true],
    eval_rules(EnabledRules, Order).

-spec eval_rules([#stp_routing_rule{}], #payment_order{}) ->
    straight_through | exception | block | no_match.
eval_rules([], _Order) ->
    no_match;
eval_rules([Rule | Rest], Order) ->
    case matches(Rule, Order) of
        true  -> Rule#stp_routing_rule.action;
        false -> eval_rules(Rest, Order)
    end.

%%% ---------------------------------------------------------- INTERNALS ---

-type condition_type() :: amount | kyc | account_status | aml | sanctions | velocity.

-spec matches(#stp_routing_rule{}, #payment_order{}) -> boolean().
matches(Rule, Order) ->
    try
        check_condition(Rule#stp_routing_rule.condition_type,
                        Rule#stp_routing_rule.condition_params,
                        Order)
    catch
        _:_ -> false
    end.

-spec check_condition(condition_type(), map(), #payment_order{}) -> boolean().
check_condition(amount, #{threshold := Threshold}, Order) ->
    Order#payment_order.amount > Threshold;

check_condition(kyc, #{required_status := Required}, Order) ->
    case mnesia:dirty_read(party, Order#payment_order.party_id) of
        [Party] -> Party#party.kyc_status =/= Required;
        []      -> true
    end;

check_condition(account_status, #{required_status := Required}, Order) ->
    case mnesia:dirty_read(account, Order#payment_order.source_account_id) of
        [Account] -> Account#account.status =/= Required;
        []        -> true
    end;

check_condition(aml, _Params, Order) ->
    case cb_aml:evaluate_transaction(Order#payment_order.party_id,
                                     Order#payment_order.amount) of
        {ok, clear}   -> false;
        {ok, flagged} -> true;
        _             -> false
    end;

check_condition(sanctions, _Params, Order) ->
    case mnesia:dirty_read(party, Order#payment_order.party_id) of
        [Party] -> maps:get(sanctions_blocked, Party#party.metadata, false);
        []      -> true
    end;

check_condition(velocity, #{max_daily_amount := MaxDaily}, Order) ->
    Today = calendar:universal_time(),
    DayStart = calendar:datetime_to_gregorian_seconds(
                   {element(1, Today), {0, 0, 0}}) * 1000,
    Txns = mnesia:dirty_index_read(transaction, Order#payment_order.party_id, party_id),
    DailyTotal = lists:foldl(fun(T, Acc) ->
        case T#transaction.created_at >= DayStart of
            true  -> Acc + T#transaction.amount;
            false -> Acc
        end
    end, 0, Txns),
    DailyTotal + Order#payment_order.amount > MaxDaily.

-spec apply_updates(#stp_routing_rule{}, map(), timestamp_ms()) -> #stp_routing_rule{}.
apply_updates(Rule, Updates, Now) ->
    R0 = case maps:find(name, Updates) of
        {ok, V0} -> Rule#stp_routing_rule{name = V0};
        error     -> Rule
    end,
    R1 = case maps:find(priority, Updates) of
        {ok, V1} -> R0#stp_routing_rule{priority = V1};
        error     -> R0
    end,
    R2 = case maps:find(condition_type, Updates) of
        {ok, V2} -> R1#stp_routing_rule{condition_type = V2};
        error     -> R1
    end,
    R3 = case maps:find(condition_params, Updates) of
        {ok, V3} -> R2#stp_routing_rule{condition_params = V3};
        error     -> R2
    end,
    R4 = case maps:find(action, Updates) of
        {ok, V4} -> R3#stp_routing_rule{action = V4};
        error     -> R3
    end,
    R5 = case maps:find(enabled, Updates) of
        {ok, V5} -> R4#stp_routing_rule{enabled = V5};
        error     -> R4
    end,
    R5#stp_routing_rule{updated_at = Now}.
