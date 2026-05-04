%% @doc TASK-079 — Governed insight generation with role-aware access controls.
%%
%% Insights summarise analytics state for a target audience. Sensitivity is
%% derived from the insight kind. Access requires the requester's role to be
%% in the insight's audience list AND to clear the sensitivity floor.
%%
%% Role hierarchy (low -> high): analyst < operator < risk_officer < admin.
-module(cb_insight_gov).
-compile({no_auto_import, [get/3]}).

-include_lib("cb_ledger/include/cb_ledger.hrl").
-include_lib("cb_analytics/include/cb_analytics.hrl").
-include_lib("cb_insights/include/cb_insights.hrl").

-export([
    generate/3,
    get/3,
    list_for_role/1,
    list_access_log/1,
    role_clears/2
]).

-spec generate(insight_kind(), binary(), [insight_role()]) ->
    {ok, uuid()} | {error, term()}.
generate(Kind, GeneratedBy, Audience)
        when is_atom(Kind), is_binary(GeneratedBy), is_list(Audience) ->
    case build_payload(Kind) of
        {error, Reason} ->
            {error, Reason};
        {ok, Payload} ->
            Sensitivity = sensitivity_for(Kind),
            Now = erlang:system_time(millisecond),
            I = #insight{
                insight_id   = new_id(),
                kind         = Kind,
                sensitivity  = Sensitivity,
                payload      = Payload,
                generated_by = GeneratedBy,
                audience     = Audience,
                created_at   = Now
            },
            case mnesia:transaction(fun() -> mnesia:write(I) end) of
                {atomic, ok} -> {ok, I#insight.insight_id};
                {aborted, R} -> {error, R}
            end
    end.

-spec get(uuid(), binary(), insight_role()) ->
    {ok, #insight{}} | {error, not_found | unauthorized | insufficient_clearance}.
get(InsightId, Accessor, Role) ->
    case read_insight(InsightId) of
        {error, not_found} ->
            log_access(InsightId, Accessor, Role, denied, not_found),
            {error, not_found};
        {ok, I} ->
            case authorized(I, Role) of
                ok ->
                    log_access(InsightId, Accessor, Role, granted, undefined),
                    {ok, I};
                {error, Reason} ->
                    log_access(InsightId, Accessor, Role, denied, Reason),
                    {error, Reason}
            end
    end.

-spec list_for_role(insight_role()) -> [#insight{}].
list_for_role(Role) ->
    {atomic, All} = mnesia:transaction(
        fun() -> mnesia:match_object(#insight{_ = '_'}) end),
    [I || I <- All,
          authorized(I, Role) =:= ok].

-spec list_access_log(uuid()) -> [#insight_access_log{}].
list_access_log(InsightId) ->
    {atomic, Logs} = mnesia:transaction(
        fun() ->
            mnesia:match_object(
                #insight_access_log{insight_id = InsightId, _ = '_'})
        end),
    lists:sort(
        fun(A, B) -> A#insight_access_log.accessed_at >= B#insight_access_log.accessed_at end,
        Logs).

-spec role_clears(insight_role(), sensitivity()) -> boolean().
role_clears(Role, Sensitivity) ->
    role_level(Role) >= sensitivity_level(Sensitivity).

%% ---------- internal ----------

read_insight(InsightId) ->
    case mnesia:transaction(fun() -> mnesia:read(insight, InsightId) end) of
        {atomic, [I]} -> {ok, I};
        {atomic, []}  -> {error, not_found};
        {aborted, R}  -> {error, R}
    end.

authorized(I, Role) ->
    case lists:member(Role, I#insight.audience) of
        false -> {error, unauthorized};
        true ->
            case role_clears(Role, I#insight.sensitivity) of
                true  -> ok;
                false -> {error, insufficient_clearance}
            end
    end.

log_access(InsightId, Accessor, Role, Decision, Reason) ->
    Log = #insight_access_log{
        access_id   = new_id(),
        insight_id  = InsightId,
        accessor    = Accessor,
        role        = Role,
        decision    = Decision,
        reason      = Reason,
        accessed_at = erlang:system_time(millisecond)
    },
    mnesia:transaction(fun() -> mnesia:write(Log) end),
    ok.

build_payload(segment_overview) ->
    Segs = cb_segmentation:list_segments(),
    {ok, #{total => length(Segs),
           active => length([S || S <- Segs,
                                  S#customer_segment.status =:= active])}};
build_payload(recommendation_summary) ->
    Pending = cb_recommendations:list_pending(),
    {ok, #{pending_count => length(Pending)}};
build_payload(churn_summary) ->
    Preds = cb_predictions:list_by_kind(churn),
    Scores = [P#prediction_score.score || P <- Preds],
    {ok, #{count        => length(Preds),
           average_score => avg(Scores)}};
build_payload(drift_summary) ->
    Monitors = cb_model_monitor:list_monitors(),
    Alerts = lists:flatmap(
        fun(M) ->
            cb_model_monitor:list_alerts_for_monitor(
                M#model_monitor.monitor_id)
        end, Monitors),
    Critical = length([A || A <- Alerts,
                            A#drift_alert.severity =:= critical]),
    {ok, #{monitors => length(Monitors),
           alerts   => length(Alerts),
           critical => Critical}};
build_payload(_) ->
    {error, unknown_insight_kind}.

sensitivity_for(segment_overview)        -> public;
sensitivity_for(recommendation_summary)  -> restricted;
sensitivity_for(churn_summary)           -> restricted;
sensitivity_for(drift_summary)           -> confidential.

role_level(analyst)      -> 1;
role_level(operator)     -> 2;
role_level(risk_officer) -> 3;
role_level(admin)        -> 4.

sensitivity_level(public)       -> 1;
sensitivity_level(restricted)   -> 2;
sensitivity_level(confidential) -> 3.

avg([]) -> 0.0;
avg(Xs) -> lists:sum(Xs) / length(Xs).

new_id() ->
    uuid:uuid_to_string(uuid:get_v4(), binary_standard).
