%%%-------------------------------------------------------------------
%% @doc Predictions: churn and anomaly scoring (P5-S1, TASK-076).
%%
%% Scoring is deterministic and rule-driven so behavior is auditable.
%%
%%   - score_churn/3 takes (EntityId, Features, FeaturesUsed) where Features
%%     is a #{key => float()} with normalized 0..1 values; high values on
%%     risk-positive keys raise the score.
%%   - score_anomaly/3 takes (EntityId, Sample, Baseline) and computes a
%%     z-score-derived score in [0, 1].
%%
%% Confidence is derived from feature coverage: more features used yields
%% a higher confidence value, capped at 1.0. The band is a coarse bucket
%% useful for downstream UIs.
%% @end
%%%-------------------------------------------------------------------
-module(cb_predictions).

-include_lib("cb_ledger/include/cb_ledger.hrl").
-include_lib("cb_analytics/include/cb_analytics.hrl").

-export([
    score_churn/3,
    score_anomaly/3,
    list_for_entity/1,
    list_by_kind/1,
    get/1
]).

-spec score_churn(uuid(), #{binary() => float()}, [binary()]) ->
    {ok, uuid(), float(), float(), confidence_band()}.
score_churn(EntityId, Features, FeaturesUsed) when is_map(Features) ->
    %% Average normalized risk indicators; clamp to [0, 1].
    Vals = maps:values(Features),
    Score = case Vals of
        [] -> 0.0;
        _  -> clamp01(lists:sum(Vals) / length(Vals))
    end,
    {Confidence, Band} = confidence(FeaturesUsed),
    {ok, Id} = persist(churn, EntityId, Score, Confidence, Band, FeaturesUsed),
    {ok, Id, Score, Confidence, Band}.

-spec score_anomaly(uuid(), float(), {float(), float()}) ->
    {ok, uuid(), float(), float(), confidence_band()}.
score_anomaly(EntityId, Sample, {Mean, Stddev}) when Stddev > 0.0 ->
    Z = abs(Sample - Mean) / Stddev,
    %% Map z to [0,1] via 1 - exp(-z/3); 3-sigma -> ~0.63 score.
    Score = clamp01(1.0 - math:exp(-Z / 3.0)),
    Used = [<<"sample">>, <<"baseline_mean">>, <<"baseline_stddev">>],
    {Confidence, Band} = confidence(Used),
    {ok, Id} = persist(anomaly, EntityId, Score, Confidence, Band, Used),
    {ok, Id, Score, Confidence, Band};
score_anomaly(EntityId, _Sample, {_Mean, _ZeroStddev}) ->
    %% Degenerate baseline: no variance = no anomaly signal.
    Used = [<<"sample">>],
    {Confidence, Band} = {0.1, low},
    {ok, Id} = persist(anomaly, EntityId, 0.0, Confidence, Band, Used),
    {ok, Id, 0.0, Confidence, Band}.

-spec list_for_entity(uuid()) -> [#prediction_score{}].
list_for_entity(EntityId) ->
    {atomic, L} = mnesia:transaction(fun() ->
        mnesia:index_read(prediction_score, EntityId, entity_id)
    end),
    L.

-spec list_by_kind(prediction_kind()) -> [#prediction_score{}].
list_by_kind(Kind) ->
    {atomic, L} = mnesia:transaction(fun() ->
        mnesia:index_read(prediction_score, Kind, kind)
    end),
    L.

-spec get(uuid()) -> {ok, #prediction_score{}} | {error, not_found}.
get(Id) ->
    case mnesia:transaction(fun() -> mnesia:read(prediction_score, Id) end) of
        {atomic, [P]} -> {ok, P};
        {atomic, []}  -> {error, not_found}
    end.

%%====================================================================
%% Internals
%%====================================================================

persist(Kind, EntityId, Score, Confidence, Band, FeaturesUsed) ->
    Id = new_id(),
    P = #prediction_score{
        prediction_id = Id,
        kind          = Kind,
        entity_id     = EntityId,
        score         = Score,
        confidence    = Confidence,
        confidence_band = Band,
        features_used = FeaturesUsed,
        computed_at   = now_ms()
    },
    {atomic, ok} = mnesia:transaction(fun() -> mnesia:write(P) end),
    {ok, Id}.

%% Confidence rises with feature coverage. 5+ features is "high".
confidence(Features) when is_list(Features) ->
    N = length(Features),
    Conf = clamp01(N / 5.0),
    Band =
        if Conf >= 0.7 -> high;
           Conf >= 0.4 -> medium;
           true        -> low
        end,
    {Conf, Band}.

clamp01(X) when X < 0.0 -> 0.0;
clamp01(X) when X > 1.0 -> 1.0;
clamp01(X) -> X.

new_id() ->
    uuid:uuid_to_string(uuid:get_v4(), binary_standard).

now_ms() ->
    erlang:system_time(millisecond).
