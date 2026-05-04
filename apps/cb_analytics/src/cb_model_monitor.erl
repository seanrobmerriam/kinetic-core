%%%-------------------------------------------------------------------
%% @doc Model monitoring, drift detection, and retraining triggers
%% (P5-S1, TASK-077).
%%
%% Drift score is computed as standardized mean shift:
%%   drift = |observed_mean - baseline_mean| / baseline_stddev
%%
%% When drift_score exceeds the monitor's drift_threshold the monitor
%% transitions to `drifting' and a #drift_alert{} is emitted. Severity
%% is graded against fixed multipliers of the threshold.
%%
%% A retraining trigger may be raised manually or automatically when one
%% or more critical alerts exist for the same model.
%% @end
%%%-------------------------------------------------------------------
-module(cb_model_monitor).

-include_lib("cb_ledger/include/cb_ledger.hrl").
-include_lib("cb_analytics/include/cb_analytics.hrl").

-export([
    register_monitor/4,
    list_monitors/0,
    get_monitor/1,
    record_sample/3,
    list_alerts_for_monitor/1,
    raise_retraining/3,
    list_triggers/0,
    acknowledge_trigger/1,
    complete_trigger/1
]).

%%====================================================================
%% Monitors
%%====================================================================

-spec register_monitor(binary(), binary(), {float(), float()}, float()) ->
    {ok, uuid()} | {error, invalid_baseline | invalid_threshold}.
register_monitor(_ModelName, _FeatureKey, {_M, Stddev}, _Thr)
        when Stddev =< 0.0 ->
    {error, invalid_baseline};
register_monitor(_ModelName, _FeatureKey, _Baseline, Threshold)
        when Threshold =< 0.0 ->
    {error, invalid_threshold};
register_monitor(ModelName, FeatureKey, {Mean, Stddev}, Threshold) ->
    Id = new_id(),
    Now = now_ms(),
    M = #model_monitor{
        monitor_id      = Id,
        model_name      = ModelName,
        feature_key     = FeatureKey,
        baseline_mean   = Mean,
        baseline_stddev = Stddev,
        drift_threshold = Threshold,
        status          = healthy,
        created_at      = Now,
        updated_at      = Now
    },
    {atomic, ok} = mnesia:transaction(fun() -> mnesia:write(M) end),
    {ok, Id}.

-spec list_monitors() -> [#model_monitor{}].
list_monitors() ->
    {atomic, L} = mnesia:transaction(fun() ->
        mnesia:foldl(fun(M, Acc) -> [M | Acc] end, [], model_monitor)
    end),
    L.

-spec get_monitor(uuid()) -> {ok, #model_monitor{}} | {error, not_found}.
get_monitor(MonitorId) ->
    case mnesia:transaction(fun() -> mnesia:read(model_monitor, MonitorId) end) of
        {atomic, [M]} -> {ok, M};
        {atomic, []}  -> {error, not_found}
    end.

%%====================================================================
%% Sample recording + drift detection
%%====================================================================

-spec record_sample(uuid(), float(), non_neg_integer()) ->
    {ok, healthy | warning | drifting, float()} | {error, not_found}.
record_sample(MonitorId, ObservedMean, SampleSize) ->
    F = fun() ->
        case mnesia:read(model_monitor, MonitorId) of
            [] ->
                {error, not_found};
            [M0] ->
                Drift = drift_score(ObservedMean, M0),
                {NewStatus, AlertOpt} =
                    classify(Drift, ObservedMean, SampleSize, M0),
                M1 = M0#model_monitor{status = NewStatus, updated_at = now_ms()},
                mnesia:write(M1),
                case AlertOpt of
                    none ->
                        ok;
                    {alert, AlertRec} ->
                        mnesia:write(AlertRec)
                end,
                {ok, NewStatus, Drift}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, {ok, S, D}}         -> {ok, S, D};
        {atomic, {error, not_found}} -> {error, not_found}
    end.

drift_score(ObservedMean, #model_monitor{baseline_mean = BM,
                                         baseline_stddev = BS}) ->
    abs(ObservedMean - BM) / BS.

classify(Drift, ObservedMean, SampleSize,
         #model_monitor{monitor_id = MonId, drift_threshold = Thr}) ->
    if
        Drift >= 2.0 * Thr ->
            {drifting, {alert, alert_rec(MonId, Drift, critical,
                                         ObservedMean, SampleSize)}};
        Drift >= Thr ->
            {drifting, {alert, alert_rec(MonId, Drift, warning,
                                         ObservedMean, SampleSize)}};
        Drift >= 0.5 * Thr ->
            {warning, {alert, alert_rec(MonId, Drift, info,
                                        ObservedMean, SampleSize)}};
        true ->
            {healthy, none}
    end.

alert_rec(MonId, Drift, Severity, Mean, N) ->
    #drift_alert{
        alert_id      = new_id(),
        monitor_id    = MonId,
        drift_score   = Drift,
        severity      = Severity,
        observed_mean = Mean,
        sample_size   = N,
        detected_at   = now_ms()
    }.

-spec list_alerts_for_monitor(uuid()) -> [#drift_alert{}].
list_alerts_for_monitor(MonitorId) ->
    {atomic, L} = mnesia:transaction(fun() ->
        mnesia:index_read(drift_alert, MonitorId, monitor_id)
    end),
    L.

%%====================================================================
%% Retraining triggers
%%====================================================================

-spec raise_retraining(binary(), binary(), [uuid()]) -> {ok, uuid()}.
raise_retraining(ModelName, Reason, AlertIds) ->
    Id = new_id(),
    Now = now_ms(),
    T = #retraining_trigger{
        trigger_id = Id,
        model_name = ModelName,
        reason     = Reason,
        alert_ids  = AlertIds,
        status     = pending,
        created_at = Now,
        updated_at = Now
    },
    {atomic, ok} = mnesia:transaction(fun() -> mnesia:write(T) end),
    {ok, Id}.

-spec list_triggers() -> [#retraining_trigger{}].
list_triggers() ->
    {atomic, L} = mnesia:transaction(fun() ->
        mnesia:foldl(fun(T, Acc) -> [T | Acc] end, [], retraining_trigger)
    end),
    L.

-spec acknowledge_trigger(uuid()) ->
    ok | {error, not_found | invalid_transition}.
acknowledge_trigger(Id) ->
    transition(Id, pending, acknowledged).

-spec complete_trigger(uuid()) ->
    ok | {error, not_found | invalid_transition}.
complete_trigger(Id) ->
    transition(Id, acknowledged, completed).

transition(Id, From, To) ->
    F = fun() ->
        case mnesia:read(retraining_trigger, Id) of
            [] ->
                {error, not_found};
            [T] when T#retraining_trigger.status =:= From ->
                mnesia:write(T#retraining_trigger{status     = To,
                                                  updated_at = now_ms()});
            [_] ->
                {error, invalid_transition}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, ok}                            -> ok;
        {atomic, {error, not_found}}            -> {error, not_found};
        {atomic, {error, invalid_transition}}   -> {error, invalid_transition}
    end.

new_id() ->
    uuid:uuid_to_string(uuid:get_v4(), binary_standard).

now_ms() ->
    erlang:system_time(millisecond).
