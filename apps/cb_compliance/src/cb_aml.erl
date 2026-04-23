%% @doc AML Rule Authoring, Suspicious Activity Queue, and Case Management.
%%
%% Provides three sub-domains in one module:
%%
%% 1. AML Rules — create and manage rules that evaluate transactions/parties.
%%    Rules have a condition type (amount_threshold, velocity, etc.) and an
%%    action (flag, block, alert, escalate) that fires when the rule matches.
%%
%% 2. Suspicious Activity — alerts raised when rules fire. Each alert enters
%%    an open queue and is reviewed by compliance staff. Outcomes: cleared or
%%    escalated to a case.
%%
%% 3. Compliance Cases — investigation records grouping related alerts.
%%    Cases progress from open → investigating → closed | escalated.
%%
%% == Rule Evaluation ==
%%
%% `evaluate_transaction/1' runs all enabled rules against a transaction
%% amount. In production, evaluation would also check party risk tier,
%% country flags, and velocity windows.
-module(cb_aml).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    %% AML rules
    create_rule/1,
    get_rule/1,
    list_rules/0,
    update_rule/2,
    delete_rule/1,
    evaluate_transaction/2,

    %% Suspicious activity
    create_alert/1,
    get_alert/1,
    list_alerts/0,
    list_alerts_by_status/1,
    review_alert/3,

    %% Cases
    create_case/1,
    get_case/1,
    list_cases/0,
    list_cases_by_status/1,
    update_case/2
]).

%%=============================================================================
%% AML Rules
%%=============================================================================

%% @doc Create a new AML rule from a map of fields.
%%
%% Required keys: name, condition_type, threshold_value, action.
-spec create_rule(map()) -> {ok, #aml_rule{}} | {error, missing_required_field | atom()}.
create_rule(Params) ->
    case validate_rule_params(Params) of
        {error, _} = Err -> Err;
        ok ->
            Now = erlang:system_time(millisecond),
            Rule = #aml_rule{
                rule_id         = uuid:get_v4_urandom(),
                name            = maps:get(name, Params),
                description     = maps:get(description, Params, <<"">>),
                condition_type  = maps:get(condition_type, Params),
                threshold_value = maps:get(threshold_value, Params),
                action          = maps:get(action, Params),
                enabled         = maps:get(enabled, Params, true),
                version         = 1,
                created_at      = Now,
                updated_at      = Now
            },
            F = fun() -> mnesia:write(aml_rule, Rule, write), Rule end,
            case mnesia:transaction(F) of
                {atomic, R} -> {ok, R};
                {aborted, Reason} -> {error, Reason}
            end
    end.

%% @doc Retrieve an AML rule by ID.
-spec get_rule(uuid()) -> {ok, #aml_rule{}} | {error, not_found}.
get_rule(RuleId) ->
    case mnesia:dirty_read(aml_rule, RuleId) of
        [] -> {error, not_found};
        [R] -> {ok, R}
    end.

%% @doc List all AML rules.
-spec list_rules() -> {ok, [#aml_rule{}]}.
list_rules() ->
    Rules = mnesia:dirty_match_object(aml_rule, mnesia:table_info(aml_rule, wild_pattern)),
    {ok, Rules}.

%% @doc Update mutable fields on a rule.
%%
%% Bumps version; enabled, description, threshold_value, action are patchable.
-spec update_rule(uuid(), map()) -> {ok, #aml_rule{}} | {error, atom()}.
update_rule(RuleId, Patch) ->
    F = fun() ->
        case mnesia:read(aml_rule, RuleId, write) of
            [] -> {error, not_found};
            [R] ->
                Now = erlang:system_time(millisecond),
                R2 = R#aml_rule{
                    description     = maps:get(description, Patch, R#aml_rule.description),
                    threshold_value = maps:get(threshold_value, Patch, R#aml_rule.threshold_value),
                    action          = maps:get(action, Patch, R#aml_rule.action),
                    enabled         = maps:get(enabled, Patch, R#aml_rule.enabled),
                    version         = R#aml_rule.version + 1,
                    updated_at      = Now
                },
                mnesia:write(aml_rule, R2, write),
                R2
        end
    end,
    case mnesia:transaction(F) of
        {atomic, {error, _} = Err} -> Err;
        {atomic, R}                -> {ok, R};
        {aborted, Reason}          -> {error, Reason}
    end.

%% @doc Delete an AML rule by ID.
-spec delete_rule(uuid()) -> ok | {error, not_found}.
delete_rule(RuleId) ->
    F = fun() ->
        case mnesia:read(aml_rule, RuleId, write) of
            [] -> {error, not_found};
            [_] ->
                mnesia:delete(aml_rule, RuleId, write),
                ok
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, Reason} -> {error, Reason}
    end.

%% @doc Evaluate all enabled rules against a transaction amount and party.
%%
%% Returns a list of `{rule_id, action}' pairs for each rule that fired.
-spec evaluate_transaction(uuid(), amount()) -> [{uuid(), aml_rule_action()}].
evaluate_transaction(PartyId, Amount) ->
    {ok, Rules} = list_rules(),
    EnabledRules = [R || R <- Rules, R#aml_rule.enabled =:= true],
    RiskTier = get_party_risk_tier(PartyId),
    lists:filtermap(
        fun(Rule) ->
            case rule_fires(Rule, Amount, RiskTier) of
                true  -> {true, {Rule#aml_rule.rule_id, Rule#aml_rule.action}};
                false -> false
            end
        end,
        EnabledRules
    ).

%%=============================================================================
%% Suspicious Activity
%%=============================================================================

%% @doc Create a new suspicious activity alert.
%%
%% Required keys in Params: party_id, rule_id, reason.
%% Optional: txn_id, risk_score, metadata.
-spec create_alert(map()) -> {ok, #suspicious_activity{}} | {error, atom()}.
create_alert(Params) ->
    case {maps:get(party_id, Params, undefined),
          maps:get(rule_id, Params, undefined),
          maps:get(reason, Params, undefined)} of
        {undefined, _, _} -> {error, missing_required_field};
        {_, undefined, _} -> {error, missing_required_field};
        {_, _, undefined} -> {error, missing_required_field};
        {PartyId, RuleId, Reason} ->
            Now = erlang:system_time(millisecond),
            Alert = #suspicious_activity{
                alert_id    = uuid:get_v4_urandom(),
                party_id    = PartyId,
                txn_id      = maps:get(txn_id, Params, undefined),
                rule_id     = RuleId,
                reason      = Reason,
                status      = open,
                risk_score  = maps:get(risk_score, Params, 0),
                metadata    = maps:get(metadata, Params, #{}),
                reviewed_by = undefined,
                reviewed_at = undefined,
                created_at  = Now,
                updated_at  = Now
            },
            F = fun() -> mnesia:write(suspicious_activity, Alert, write), Alert end,
            case mnesia:transaction(F) of
                {atomic, A} -> {ok, A};
                {aborted, Reason2} -> {error, Reason2}
            end
    end.

%% @doc Retrieve a suspicious activity alert by ID.
-spec get_alert(uuid()) -> {ok, #suspicious_activity{}} | {error, not_found}.
get_alert(AlertId) ->
    case mnesia:dirty_read(suspicious_activity, AlertId) of
        [] -> {error, not_found};
        [A] -> {ok, A}
    end.

%% @doc List all suspicious activity alerts.
-spec list_alerts() -> {ok, [#suspicious_activity{}]}.
list_alerts() ->
    Alerts = mnesia:dirty_match_object(
        suspicious_activity,
        mnesia:table_info(suspicious_activity, wild_pattern)
    ),
    {ok, Alerts}.

%% @doc List alerts filtered by status.
-spec list_alerts_by_status(suspicious_activity_status()) -> {ok, [#suspicious_activity{}]}.
list_alerts_by_status(Status) ->
    Alerts = mnesia:dirty_index_read(suspicious_activity, Status, status),
    {ok, Alerts}.

%% @doc Review an alert: either clear it or escalate it to a case.
%%
%% ReviewerId is the UUID of the compliance officer performing the review.
-spec review_alert(uuid(), cleared | escalated, uuid()) ->
    {ok, #suspicious_activity{}} | {error, atom()}.
review_alert(AlertId, Decision, ReviewerId)
        when Decision =:= cleared; Decision =:= escalated ->
    F = fun() ->
        case mnesia:read(suspicious_activity, AlertId, write) of
            [] ->
                {error, not_found};
            [A] when A#suspicious_activity.status =/= open,
                     A#suspicious_activity.status =/= under_review ->
                {error, invalid_alert_status};
            [A] ->
                Now = erlang:system_time(millisecond),
                A2 = A#suspicious_activity{
                    status      = Decision,
                    reviewed_by = ReviewerId,
                    reviewed_at = Now,
                    updated_at  = Now
                },
                mnesia:write(suspicious_activity, A2, write),
                A2
        end
    end,
    case mnesia:transaction(F) of
        {atomic, {error, _} = Err} -> Err;
        {atomic, A}                -> {ok, A};
        {aborted, Reason}          -> {error, Reason}
    end;
review_alert(_AlertId, _Decision, _ReviewerId) ->
    {error, invalid_alert_status}.

%%=============================================================================
%% Compliance Cases
%%=============================================================================

%% @doc Create a compliance investigation case.
%%
%% Required keys in Params: party_id, alert_ids, summary.
%% Optional: assignee.
-spec create_case(map()) -> {ok, #aml_case{}} | {error, atom()}.
create_case(Params) ->
    case {maps:get(party_id, Params, undefined),
          maps:get(alert_ids, Params, undefined),
          maps:get(summary, Params, undefined)} of
        {undefined, _, _} -> {error, missing_required_field};
        {_, undefined, _} -> {error, missing_required_field};
        {_, _, undefined} -> {error, missing_required_field};
        {PartyId, AlertIds, Summary} ->
            Now = erlang:system_time(millisecond),
            Case = #aml_case{
                case_id    = uuid:get_v4_urandom(),
                party_id   = PartyId,
                alert_ids  = AlertIds,
                status     = open,
                assignee   = maps:get(assignee, Params, undefined),
                summary    = Summary,
                resolution = undefined,
                closed_at  = undefined,
                created_at = Now,
                updated_at = Now
            },
            F = fun() -> mnesia:write(aml_case, Case, write), Case end,
            case mnesia:transaction(F) of
                {atomic, C} -> {ok, C};
                {aborted, Reason} -> {error, Reason}
            end
    end.

%% @doc Retrieve a compliance case by ID.
-spec get_case(uuid()) -> {ok, #aml_case{}} | {error, not_found}.
get_case(CaseId) ->
    case mnesia:dirty_read(aml_case, CaseId) of
        [] -> {error, not_found};
        [C] -> {ok, C}
    end.

%% @doc List all compliance cases.
-spec list_cases() -> {ok, [#aml_case{}]}.
list_cases() ->
    Cases = mnesia:dirty_match_object(aml_case, mnesia:table_info(aml_case, wild_pattern)),
    {ok, Cases}.

%% @doc List cases filtered by status.
-spec list_cases_by_status(aml_case_status()) -> {ok, [#aml_case{}]}.
list_cases_by_status(Status) ->
    Cases = mnesia:dirty_index_read(aml_case, Status, status),
    {ok, Cases}.

%% @doc Update mutable fields on a compliance case.
%%
%% Patchable: status, assignee, summary, resolution.
%% Closing the case sets closed_at timestamp.
-spec update_case(uuid(), map()) -> {ok, #aml_case{}} | {error, atom()}.
update_case(CaseId, Patch) ->
    F = fun() ->
        case mnesia:read(aml_case, CaseId, write) of
            [] -> {error, not_found};
            [C] ->
                Now = erlang:system_time(millisecond),
                NewStatus = maps:get(status, Patch, C#aml_case.status),
                ClosedAt = case NewStatus of
                    closed    -> Now;
                    escalated -> Now;
                    _         -> C#aml_case.closed_at
                end,
                C2 = C#aml_case{
                    status     = NewStatus,
                    assignee   = maps:get(assignee, Patch, C#aml_case.assignee),
                    summary    = maps:get(summary, Patch, C#aml_case.summary),
                    resolution = maps:get(resolution, Patch, C#aml_case.resolution),
                    closed_at  = ClosedAt,
                    updated_at = Now
                },
                mnesia:write(aml_case, C2, write),
                C2
        end
    end,
    case mnesia:transaction(F) of
        {atomic, {error, _} = Err} -> Err;
        {atomic, C}                -> {ok, C};
        {aborted, Reason}          -> {error, Reason}
    end.

%%=============================================================================
%% Internal
%%=============================================================================

-spec validate_rule_params(map()) -> ok | {error, missing_required_field | invalid_aml_rule}.
validate_rule_params(Params) ->
    Required = [name, condition_type, threshold_value, action],
    case lists:all(fun(K) -> maps:is_key(K, Params) end, Required) of
        false -> {error, missing_required_field};
        true  ->
            ValidConditions = [amount_threshold, country_risk, frequency, velocity, pattern],
            ValidActions    = [flag, block, alert, escalate],
            CT = maps:get(condition_type, Params),
            A  = maps:get(action, Params),
            case {lists:member(CT, ValidConditions), lists:member(A, ValidActions)} of
                {true, true}   -> ok;
                _              -> {error, invalid_aml_rule}
            end
    end.

-spec rule_fires(#aml_rule{}, amount(), risk_tier()) -> boolean().
rule_fires(#aml_rule{condition_type = amount_threshold, threshold_value = TV}, Amount, _) ->
    Amount >= TV;
rule_fires(#aml_rule{condition_type = country_risk}, _Amount, RiskTier) ->
    RiskTier =:= high orelse RiskTier =:= critical;
rule_fires(#aml_rule{condition_type = velocity, threshold_value = TV}, Amount, _) ->
    Amount >= TV;
rule_fires(#aml_rule{condition_type = frequency}, _Amount, RiskTier) ->
    RiskTier =:= critical;
rule_fires(#aml_rule{condition_type = pattern}, _Amount, RiskTier) ->
    RiskTier =:= high orelse RiskTier =:= critical.

-spec get_party_risk_tier(uuid()) -> risk_tier().
get_party_risk_tier(PartyId) ->
    case mnesia:dirty_read(party, PartyId) of
        [P] -> P#party.risk_tier;
        []  -> low
    end.
