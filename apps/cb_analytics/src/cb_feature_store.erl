%%%-------------------------------------------------------------------
%% @doc Feature store and governed pipelines (P5-S1, TASK-074).
%%
%% Provides:
%%   - Pipeline registration and lifecycle (active/retired)
%%   - Feature definition and lookup by stable feature_key
%%   - Per-entity feature value writes and reads
%%
%% Pipelines are stored declaratively; orchestration is handled by
%% callers. Feature values are append-only; the latest value for an
%% (entity, feature) pair is recovered by sorting on computed_at.
%% @end
%%%-------------------------------------------------------------------
-module(cb_feature_store).

-include_lib("cb_ledger/include/cb_ledger.hrl").
-include_lib("cb_analytics/include/cb_analytics.hrl").

-export([
    register_pipeline/3,
    list_pipelines/0,
    set_pipeline_status/2,
    register_feature/5,
    list_features/0,
    get_feature/1,
    write_value/3,
    latest_value/2,
    list_values_for_entity/1
]).

%%====================================================================
%% Pipelines
%%====================================================================

-spec register_pipeline(binary(), binary(), pos_integer()) -> {ok, uuid()}.
register_pipeline(Name, Description, ScheduleMs) when ScheduleMs > 0 ->
    PipelineId = new_id(),
    Now = now_ms(),
    Pipeline = #feature_pipeline{
        pipeline_id = PipelineId,
        name        = Name,
        description = Description,
        schedule_ms = ScheduleMs,
        status      = registered,
        last_run_at = undefined,
        created_at  = Now
    },
    {atomic, ok} = mnesia:transaction(fun() -> mnesia:write(Pipeline) end),
    {ok, PipelineId}.

-spec list_pipelines() -> [#feature_pipeline{}].
list_pipelines() ->
    {atomic, L} = mnesia:transaction(fun() ->
        mnesia:foldl(fun(P, Acc) -> [P | Acc] end, [], feature_pipeline)
    end),
    L.

-spec set_pipeline_status(uuid(), pipeline_status()) -> ok | {error, not_found}.
set_pipeline_status(PipelineId, NewStatus) ->
    F = fun() ->
        case mnesia:read(feature_pipeline, PipelineId) of
            [P] ->
                mnesia:write(P#feature_pipeline{status = NewStatus});
            [] ->
                {error, not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, ok}                  -> ok;
        {atomic, {error, not_found}}  -> {error, not_found}
    end.

%%====================================================================
%% Feature definitions
%%====================================================================

-spec register_feature(binary(), uuid(), binary(),
                       feature_value_type(), binary()) ->
    {ok, uuid()} | {error, pipeline_not_found | duplicate_key}.
register_feature(FeatureKey, PipelineId, Description, ValueType, Owner) ->
    F = fun() ->
        case mnesia:read(feature_pipeline, PipelineId) of
            [] ->
                {error, pipeline_not_found};
            [_] ->
                case mnesia:index_read(feature_definition, FeatureKey, feature_key) of
                    [_ | _] ->
                        {error, duplicate_key};
                    [] ->
                        Id = new_id(),
                        Now = now_ms(),
                        Def = #feature_definition{
                            feature_id  = Id,
                            feature_key = FeatureKey,
                            pipeline_id = PipelineId,
                            description = Description,
                            value_type  = ValueType,
                            owner       = Owner,
                            created_at  = Now,
                            updated_at  = Now
                        },
                        mnesia:write(Def),
                        {ok, Id}
                end
        end
    end,
    case mnesia:transaction(F) of
        {atomic, {ok, Id}}     -> {ok, Id};
        {atomic, {error, R}}   -> {error, R}
    end.

-spec list_features() -> [#feature_definition{}].
list_features() ->
    {atomic, L} = mnesia:transaction(fun() ->
        mnesia:foldl(fun(D, Acc) -> [D | Acc] end, [], feature_definition)
    end),
    L.

-spec get_feature(binary()) -> {ok, #feature_definition{}} | {error, not_found}.
get_feature(FeatureKey) ->
    F = fun() -> mnesia:index_read(feature_definition, FeatureKey, feature_key) end,
    case mnesia:transaction(F) of
        {atomic, [Def | _]} -> {ok, Def};
        {atomic, []}        -> {error, not_found}
    end.

%%====================================================================
%% Values
%%====================================================================

-spec write_value(binary(), uuid(), binary()) ->
    {ok, uuid()} | {error, feature_not_found}.
write_value(FeatureKey, EntityId, Value) ->
    F = fun() ->
        case mnesia:index_read(feature_definition, FeatureKey, feature_key) of
            [] ->
                {error, feature_not_found};
            [_ | _] ->
                Id = new_id(),
                FV = #feature_value{
                    value_id    = Id,
                    feature_key = FeatureKey,
                    entity_id   = EntityId,
                    value       = Value,
                    computed_at = now_ms()
                },
                mnesia:write(FV),
                {ok, Id}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, {ok, Id}}      -> {ok, Id};
        {atomic, {error, R}}    -> {error, R}
    end.

-spec latest_value(binary(), uuid()) ->
    {ok, #feature_value{}} | {error, not_found}.
latest_value(FeatureKey, EntityId) ->
    {atomic, L} = mnesia:transaction(fun() ->
        Matches = mnesia:index_read(feature_value, FeatureKey, feature_key),
        [V || V <- Matches, V#feature_value.entity_id =:= EntityId]
    end),
    case L of
        [] ->
            {error, not_found};
        Vs ->
            Sorted = lists:sort(
                fun(A, B) ->
                    A#feature_value.computed_at >= B#feature_value.computed_at
                end, Vs),
            {ok, hd(Sorted)}
    end.

-spec list_values_for_entity(uuid()) -> [#feature_value{}].
list_values_for_entity(EntityId) ->
    {atomic, L} = mnesia:transaction(fun() ->
        mnesia:index_read(feature_value, EntityId, entity_id)
    end),
    L.

%%====================================================================
%% Helpers
%%====================================================================

new_id() ->
    uuid:uuid_to_string(uuid:get_v4(), binary_standard).

now_ms() ->
    erlang:system_time(millisecond).
