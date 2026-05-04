%% @doc TASK-078 — Natural-language analytics query gateway.
%%
%% Deterministic keyword-based intent extraction. No LLM dependencies; the
%% gateway recognises a fixed set of analytical intents and routes parsed
%% queries to the cb_analytics modules.
%%
%% Adding a new intent requires:
%%   1. Add atom to nl_intent() in cb_insights.hrl
%%   2. Add a clause to detect_intent/1
%%   3. Add a clause to dispatch/2
-module(cb_nl_query).
-compile({no_auto_import, [get/1]}).

-include_lib("cb_ledger/include/cb_ledger.hrl").
-include_lib("cb_analytics/include/cb_analytics.hrl").
-include_lib("cb_insights/include/cb_insights.hrl").

-export([
    submit/2,
    parse/1,
    execute/1,
    get/1,
    list_recent/1
]).

-type submit_result() :: {ok, uuid(), nl_intent()} | {error, term()}.

-spec submit(binary(), binary()) -> submit_result().
submit(SubmittedBy, Text) when is_binary(SubmittedBy), is_binary(Text) ->
    {Intent, Params} = parse(Text),
    Now = erlang:system_time(millisecond),
    Q = #nl_query{
        query_id     = new_id(),
        submitted_by = SubmittedBy,
        raw_text     = Text,
        intent       = Intent,
        params       = Params,
        status       = parsed,
        result       = undefined,
        error        = undefined,
        created_at   = Now,
        updated_at   = Now
    },
    case mnesia:transaction(fun() -> mnesia:write(Q) end) of
        {atomic, ok}     -> {ok, Q#nl_query.query_id, Intent};
        {aborted, R}     -> {error, R}
    end.

-spec parse(binary()) -> {nl_intent(), #{atom() => term()}}.
parse(Text) when is_binary(Text) ->
    Lower = string:lowercase(Text),
    Intent = detect_intent(Lower),
    {Intent, extract_params(Intent, Lower)}.

-spec execute(uuid()) -> {ok, term()} | {error, term()}.
execute(QueryId) ->
    case get(QueryId) of
        {error, not_found} ->
            {error, not_found};
        {ok, Q} ->
            case dispatch(Q#nl_query.intent, Q#nl_query.params) of
                {ok, Result} ->
                    update_status(QueryId, executed, Result, undefined),
                    {ok, Result};
                {error, Reason} ->
                    Err = atom_to_binary(Reason, utf8),
                    update_status(QueryId, failed, undefined, Err),
                    {error, Reason}
            end
    end.

-spec get(uuid()) -> {ok, #nl_query{}} | {error, not_found}.
get(QueryId) ->
    case mnesia:transaction(fun() -> mnesia:read(nl_query, QueryId) end) of
        {atomic, [Q]} -> {ok, Q};
        {atomic, []}  -> {error, not_found};
        {aborted, R}  -> {error, R}
    end.

-spec list_recent(pos_integer()) -> [#nl_query{}].
list_recent(Limit) when is_integer(Limit), Limit > 0 ->
    {atomic, All} = mnesia:transaction(
        fun() -> mnesia:match_object(#nl_query{_ = '_'}) end),
    Sorted = lists:sort(
        fun(A, B) -> A#nl_query.created_at > B#nl_query.created_at end, All),
    lists:sublist(Sorted, Limit).

%% ---------- internal ----------

detect_intent(Text) ->
    case {contains(Text, <<"segment">>),
          contains(Text, <<"recommendation">>),
          contains(Text, <<"prediction">>) orelse contains(Text, <<"churn">>),
          contains(Text, <<"drift">>) orelse contains(Text, <<"alert">>),
          contains(Text, <<"feature">>) orelse contains(Text, <<"value">>)} of
        {true,  _, _, _, _}    -> list_segments;
        {_, true, _, _, _}     -> list_pending_recommendations;
        {_, _, true, _, _}     -> list_recent_predictions;
        {_, _, _, true, _}     -> list_drift_alerts;
        {_, _, _, _, true}     -> feature_latest;
        _                      -> unknown
    end.

extract_params(feature_latest, Text) ->
    case extract_quoted(Text) of
        {ok, Key} -> #{feature_key => Key};
        none      -> #{}
    end;
extract_params(list_recent_predictions, Text) ->
    case contains(Text, <<"anomaly">>) of
        true  -> #{kind => anomaly};
        false -> #{kind => churn}
    end;
extract_params(_, _) ->
    #{}.

dispatch(list_segments, _) ->
    {ok, [segment_to_map(S) || S <- cb_segmentation:list_segments()]};
dispatch(list_pending_recommendations, _) ->
    {ok, [rec_to_map(R) || R <- cb_recommendations:list_pending()]};
dispatch(list_recent_predictions, #{kind := K}) ->
    {ok, [pred_to_map(P) || P <- cb_predictions:list_by_kind(K)]};
dispatch(list_recent_predictions, _) ->
    {ok, [pred_to_map(P) || P <- cb_predictions:list_by_kind(churn)]};
dispatch(list_drift_alerts, _) ->
    Monitors = cb_model_monitor:list_monitors(),
    Alerts = lists:flatmap(
        fun(M) ->
            cb_model_monitor:list_alerts_for_monitor(
                M#model_monitor.monitor_id)
        end, Monitors),
    {ok, [alert_to_map(A) || A <- Alerts]};
dispatch(feature_latest, #{feature_key := K}) ->
    case cb_feature_store:get_feature(K) of
        {ok, F}            -> {ok, feature_to_map(F)};
        {error, not_found} -> {error, feature_not_found}
    end;
dispatch(feature_latest, _) ->
    {error, missing_feature_key};
dispatch(unknown, _) ->
    {error, intent_not_recognized}.

update_status(QueryId, Status, Result, Err) ->
    Now = erlang:system_time(millisecond),
    mnesia:transaction(
        fun() ->
            case mnesia:read(nl_query, QueryId) of
                [Q0] ->
                    mnesia:write(Q0#nl_query{
                        status = Status,
                        result = Result,
                        error  = Err,
                        updated_at = Now});
                [] -> ok
            end
        end).

contains(Hay, Needle) ->
    binary:match(Hay, Needle) =/= nomatch.

%% Extract the first quoted token from a binary, returning {ok, Token} or none.
extract_quoted(Text) ->
    case re:run(Text, <<"['\"]([^'\"]+)['\"]">>, [{capture, [1], binary}]) of
        {match, [Token]} -> {ok, Token};
        _                -> none
    end.

new_id() ->
    uuid:uuid_to_string(uuid:get_v4(), binary_standard).

segment_to_map(S) ->
    #{segment_id => S#customer_segment.segment_id,
      name       => S#customer_segment.name,
      status     => S#customer_segment.status}.

rec_to_map(R) ->
    #{recommendation_id => R#product_recommendation.recommendation_id,
      party_id          => R#product_recommendation.party_id,
      product_code      => R#product_recommendation.product_code,
      score             => R#product_recommendation.score}.

pred_to_map(P) ->
    #{prediction_id   => P#prediction_score.prediction_id,
      kind            => P#prediction_score.kind,
      entity_id       => P#prediction_score.entity_id,
      score           => P#prediction_score.score,
      confidence_band => P#prediction_score.confidence_band}.

alert_to_map(A) ->
    #{alert_id    => A#drift_alert.alert_id,
      monitor_id  => A#drift_alert.monitor_id,
      severity    => A#drift_alert.severity,
      drift_score => A#drift_alert.drift_score}.

feature_to_map(F) ->
    #{feature_id  => F#feature_definition.feature_id,
      feature_key => F#feature_definition.feature_key,
      value_type  => F#feature_definition.value_type}.
