%% @doc CT tests for P5-S1 analytics platform (TASK-074..077).
-module(cb_analytics_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").
-include_lib("cb_analytics/include/cb_analytics.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1,
         init_per_testcase/2, end_per_testcase/2]).

-export([
    feature_pipeline_lifecycle/1,
    feature_value_write_and_latest/1,
    register_feature_unknown_pipeline/1,
    segment_define_and_assign/1,
    segment_assign_retired_fails/1,
    recommendation_lifecycle/1,
    recommendation_invalid_transition/1,
    churn_score_in_range/1,
    churn_score_zero_features/1,
    anomaly_score_degenerate_baseline/1,
    anomaly_score_high_z/1,
    monitor_drift_warning/1,
    monitor_drift_critical/1,
    retraining_trigger_lifecycle/1
]).

all() ->
    [feature_pipeline_lifecycle,
     feature_value_write_and_latest,
     register_feature_unknown_pipeline,
     segment_define_and_assign,
     segment_assign_retired_fails,
     recommendation_lifecycle,
     recommendation_invalid_transition,
     churn_score_in_range,
     churn_score_zero_features,
     anomaly_score_degenerate_baseline,
     anomaly_score_high_z,
     monitor_drift_warning,
     monitor_drift_critical,
     retraining_trigger_lifecycle].

init_per_suite(Config) ->
    mnesia:start(),
    cb_schema:create_tables(),
    Config.

end_per_suite(_Config) ->
    mnesia:stop(),
    mnesia:delete_schema([node()]),
    ok.

init_per_testcase(_TC, Config) ->
    [mnesia:clear_table(T) ||
        T <- [feature_pipeline, feature_definition, feature_value,
              customer_segment, segment_membership, product_recommendation,
              prediction_score, model_monitor, drift_alert,
              retraining_trigger]],
    Config.

end_per_testcase(_TC, _Config) -> ok.

%% TASK-074

feature_pipeline_lifecycle(_) ->
    {ok, PId} = cb_feature_store:register_pipeline(
                  <<"daily">>, <<"daily aggregates">>, 86400000),
    ?assertEqual(ok, cb_feature_store:set_pipeline_status(PId, active)),
    [P] = cb_feature_store:list_pipelines(),
    ?assertEqual(active, P#feature_pipeline.status),
    ?assertEqual(ok, cb_feature_store:set_pipeline_status(PId, retired)),
    ?assertEqual({error, not_found},
                 cb_feature_store:set_pipeline_status(<<"missing">>, active)).

feature_value_write_and_latest(_) ->
    {ok, PId} = cb_feature_store:register_pipeline(
                  <<"p">>, <<"d">>, 60000),
    cb_feature_store:set_pipeline_status(PId, active),
    {ok, _FId} = cb_feature_store:register_feature(
                   <<"balance">>, PId, <<"current balance">>,
                   numeric, <<"team-a">>),
    {ok, _} = cb_feature_store:write_value(<<"balance">>, <<"e1">>, 100),
    timer:sleep(2),
    {ok, _} = cb_feature_store:write_value(<<"balance">>, <<"e1">>, 200),
    {ok, V} = cb_feature_store:latest_value(<<"balance">>, <<"e1">>),
    ?assertEqual(200, V#feature_value.value).

register_feature_unknown_pipeline(_) ->
    Result = cb_feature_store:register_feature(
               <<"k">>, <<"missing-pipeline">>, <<"d">>, numeric, <<"o">>),
    ?assertMatch({error, _}, Result).

%% TASK-075a

segment_define_and_assign(_) ->
    {ok, SId} = cb_segmentation:define_segment(
                  <<"high-value">>, <<"top tier">>, #{min_balance => 10000}),
    {ok, _} = cb_segmentation:assign(SId, <<"party-1">>),
    Members = cb_segmentation:list_members(SId),
    ?assertEqual(1, length(Members)).

segment_assign_retired_fails(_) ->
    {ok, SId} = cb_segmentation:define_segment(
                  <<"old">>, <<"d">>, #{}),
    ok = cb_segmentation:retire_segment(SId),
    ?assertMatch({error, _}, cb_segmentation:assign(SId, <<"p">>)).

%% TASK-075b

recommendation_lifecycle(_) ->
    {ok, RId} = cb_recommendations:create(
                  <<"p1">>, <<"savings-x">>, 0.8, <<"high inflow">>),
    ?assertEqual(ok, cb_recommendations:transition(RId, delivered)),
    ?assertEqual(ok, cb_recommendations:transition(RId, accepted)).

recommendation_invalid_transition(_) ->
    {ok, RId} = cb_recommendations:create(
                  <<"p1">>, <<"x">>, 0.5, <<"r">>),
    ?assertEqual({error, invalid_transition},
                 cb_recommendations:transition(RId, accepted)).

%% TASK-076

churn_score_in_range(_) ->
    {ok, _, Score, Conf, Bnd} = cb_predictions:score_churn(
        <<"e1">>, #{a => 0.5, b => 0.7, c => 0.2},
        [<<"a">>, <<"b">>, <<"c">>]),
    ?assert(Score >= 0.0 andalso Score =< 1.0),
    ?assert(Conf >= 0.0 andalso Conf =< 1.0),
    ?assert(lists:member(Bnd, [low, medium, high])).

churn_score_zero_features(_) ->
    {ok, _, Score, _, _} = cb_predictions:score_churn(
        <<"e1">>, #{}, []),
    ?assertEqual(0.0, Score).

anomaly_score_degenerate_baseline(_) ->
    {ok, _, Score, _Conf, Bnd} = cb_predictions:score_anomaly(
        <<"e1">>, 100.0, {100.0, 0.0}),
    ?assertEqual(0.0, Score),
    ?assertEqual(low, Bnd).

anomaly_score_high_z(_) ->
    {ok, _, Score, _, _} = cb_predictions:score_anomaly(
        <<"e1">>, 100.0, {0.0, 1.0}),
    ?assert(Score > 0.9).

%% TASK-077

monitor_drift_warning(_) ->
    {ok, MId} = cb_model_monitor:register_monitor(
                  <<"churn-v1">>, <<"f1">>, {100.0, 10.0}, 1.0),
    {ok, Status, Drift} = cb_model_monitor:record_sample(MId, 110.0, 50),
    ?assertEqual(drifting, Status),
    ?assert(Drift >= 1.0),
    Alerts = cb_model_monitor:list_alerts_for_monitor(MId),
    ?assert(length(Alerts) >= 1).

monitor_drift_critical(_) ->
    {ok, MId} = cb_model_monitor:register_monitor(
                  <<"m">>, <<"f">>, {100.0, 10.0}, 1.0),
    {ok, drifting, _} = cb_model_monitor:record_sample(MId, 200.0, 100),
    [A | _] = cb_model_monitor:list_alerts_for_monitor(MId),
    ?assertEqual(critical, A#drift_alert.severity).

retraining_trigger_lifecycle(_) ->
    {ok, MId} = cb_model_monitor:register_monitor(
                  <<"m">>, <<"f">>, {0.0, 1.0}, 1.0),
    {ok, _, _} = cb_model_monitor:record_sample(MId, 5.0, 30),
    [A | _] = cb_model_monitor:list_alerts_for_monitor(MId),
    {ok, TId} = cb_model_monitor:raise_retraining(
                  <<"m">>, <<"drift">>,
                  [A#drift_alert.alert_id]),
    ?assertEqual(ok, cb_model_monitor:acknowledge_trigger(TId)),
    ?assertEqual(ok, cb_model_monitor:complete_trigger(TId)),
    ?assertEqual({error, invalid_transition},
                 cb_model_monitor:acknowledge_trigger(TId)).
