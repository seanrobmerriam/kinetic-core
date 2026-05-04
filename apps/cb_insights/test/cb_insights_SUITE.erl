%% @doc CT tests for P5-S2 conversational + insights platform
%% (TASK-078..080).
-module(cb_insights_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").
-include_lib("cb_analytics/include/cb_analytics.hrl").
-include_lib("cb_insights/include/cb_insights.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1,
         init_per_testcase/2, end_per_testcase/2]).

-export([
    nl_parse_segments/1,
    nl_parse_recommendations/1,
    nl_parse_predictions_anomaly/1,
    nl_parse_drift/1,
    nl_parse_unknown/1,
    nl_submit_and_execute/1,
    nl_execute_unknown_query/1,
    insight_generate_segment_overview/1,
    insight_generate_drift_summary/1,
    insight_role_granted/1,
    insight_role_unauthorized/1,
    insight_role_insufficient_clearance/1,
    insight_list_for_role/1,
    insight_access_log_records_decisions/1,
    byok_register_and_activate/1,
    byok_invalid_key_size/1,
    byok_encrypt_requires_active/1,
    byok_encrypt_decrypt_roundtrip/1,
    byok_rotate_then_decrypt/1,
    byok_revoke_blocks_decrypt/1,
    byok_access_log_records_operations/1
]).

all() ->
    [nl_parse_segments,
     nl_parse_recommendations,
     nl_parse_predictions_anomaly,
     nl_parse_drift,
     nl_parse_unknown,
     nl_submit_and_execute,
     nl_execute_unknown_query,
     insight_generate_segment_overview,
     insight_generate_drift_summary,
     insight_role_granted,
     insight_role_unauthorized,
     insight_role_insufficient_clearance,
     insight_list_for_role,
     insight_access_log_records_decisions,
     byok_register_and_activate,
     byok_invalid_key_size,
     byok_encrypt_requires_active,
     byok_encrypt_decrypt_roundtrip,
     byok_rotate_then_decrypt,
     byok_revoke_blocks_decrypt,
     byok_access_log_records_operations].

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
              retraining_trigger,
              nl_query, insight, insight_access_log,
              byok_key, byok_access_log]],
    Config.

end_per_testcase(_TC, _Config) ->
    ok.

%%====================================================================
%% NL query gateway (TASK-078)
%%====================================================================

nl_parse_segments(_) ->
    {list_segments, _} = cb_nl_query:parse(<<"show me all segments">>).

nl_parse_recommendations(_) ->
    {list_pending_recommendations, _} =
        cb_nl_query:parse(<<"list pending recommendations">>).

nl_parse_predictions_anomaly(_) ->
    {list_recent_predictions, P} =
        cb_nl_query:parse(<<"recent anomaly predictions">>),
    ?assertEqual(anomaly, maps:get(kind, P)).

nl_parse_drift(_) ->
    {list_drift_alerts, _} = cb_nl_query:parse(<<"any drift alerts">>).

nl_parse_unknown(_) ->
    {unknown, _} = cb_nl_query:parse(<<"hello world">>).

nl_submit_and_execute(_) ->
    %% Make a segment so there's something to list
    {ok, _SId} = cb_segmentation:define_segment(
        <<"vip">>, <<"VIP customers">>, [{min_balance, 1000}]),
    {ok, QId, list_segments} =
        cb_nl_query:submit(<<"analyst-1">>, <<"show me segments">>),
    {ok, Result} = cb_nl_query:execute(QId),
    ?assert(is_map(Result) orelse is_list(Result)),
    {ok, Q} = cb_nl_query:get(QId),
    ?assertEqual(executed, Q#nl_query.status).

nl_execute_unknown_query(_) ->
    {error, not_found} = cb_nl_query:execute(<<"missing-id">>).

%%====================================================================
%% Governed insights (TASK-079)
%%====================================================================

insight_generate_segment_overview(_) ->
    {ok, _SId} = cb_segmentation:define_segment(
        <<"savers">>, <<"Saver segment">>, []),
    {ok, IId} = cb_insight_gov:generate(
        segment_overview, <<"sys">>, [analyst, operator]),
    {ok, I} = cb_insight_gov:get(IId, <<"alice">>, analyst),
    ?assertEqual(segment_overview, I#insight.kind),
    ?assertEqual(public, I#insight.sensitivity).

insight_generate_drift_summary(_) ->
    {ok, IId} = cb_insight_gov:generate(
        drift_summary, <<"sys">>, [risk_officer, admin]),
    {ok, I} = cb_insight_gov:get(IId, <<"bob">>, risk_officer),
    ?assertEqual(confidential, I#insight.sensitivity).

insight_role_granted(_) ->
    {ok, IId} = cb_insight_gov:generate(
        recommendation_summary, <<"sys">>, [operator, risk_officer, admin]),
    {ok, _I} = cb_insight_gov:get(IId, <<"op-1">>, operator).

insight_role_unauthorized(_) ->
    %% audience excludes analyst
    {ok, IId} = cb_insight_gov:generate(
        churn_summary, <<"sys">>, [risk_officer, admin]),
    {error, unauthorized} = cb_insight_gov:get(IId, <<"a-1">>, analyst).

insight_role_insufficient_clearance(_) ->
    %% drift_summary is confidential; analyst clears only public
    {ok, IId} = cb_insight_gov:generate(
        drift_summary, <<"sys">>, [analyst, operator, risk_officer, admin]),
    {error, insufficient_clearance} =
        cb_insight_gov:get(IId, <<"a-1">>, analyst).

insight_list_for_role(_) ->
    {ok, _} = cb_insight_gov:generate(
        segment_overview, <<"sys">>, [analyst, operator, risk_officer, admin]),
    {ok, _} = cb_insight_gov:generate(
        drift_summary, <<"sys">>, [analyst, risk_officer, admin]),
    Listed = cb_insight_gov:list_for_role(analyst),
    %% analyst clears only public => sees only segment_overview
    Kinds = [I#insight.kind || I <- Listed],
    ?assert(lists:member(segment_overview, Kinds)),
    ?assertNot(lists:member(drift_summary, Kinds)).

insight_access_log_records_decisions(_) ->
    {ok, IId} = cb_insight_gov:generate(
        drift_summary, <<"sys">>, [analyst, admin]),
    %% analyst denied (insufficient_clearance), admin granted
    {error, insufficient_clearance} =
        cb_insight_gov:get(IId, <<"a-1">>, analyst),
    {ok, _} = cb_insight_gov:get(IId, <<"adm-1">>, admin),
    Logs = cb_insight_gov:list_access_log(IId),
    Decisions = [L#insight_access_log.decision || L <- Logs],
    ?assert(lists:member(granted, Decisions)),
    ?assert(lists:member(denied,  Decisions)).

%%====================================================================
%% BYOK (TASK-080)
%%====================================================================

byok_register_and_activate(_) ->
    Key = crypto:strong_rand_bytes(32),
    {ok, KId} = cb_byok:register_key(<<"tenant-a">>, Key, <<"AES-256-GCM">>),
    {ok, K} = cb_byok:get_key(KId),
    ?assertEqual(pending, K#byok_key.status),
    ok = cb_byok:activate(KId),
    {ok, K2} = cb_byok:get_key(KId),
    ?assertEqual(active, K2#byok_key.status).

byok_invalid_key_size(_) ->
    Bad = crypto:strong_rand_bytes(16),
    {error, _} = cb_byok:register_key(<<"t">>, Bad, <<"AES-256-GCM">>).

byok_encrypt_requires_active(_) ->
    Key = crypto:strong_rand_bytes(32),
    {ok, KId} = cb_byok:register_key(<<"t">>, Key, <<"AES-256-GCM">>),
    {error, _} =
        cb_byok:encrypt(KId, <<"hello">>, <<"u">>, <<"test">>).

byok_encrypt_decrypt_roundtrip(_) ->
    Key = crypto:strong_rand_bytes(32),
    {ok, KId} = cb_byok:register_key(<<"t">>, Key, <<"AES-256-GCM">>),
    ok = cb_byok:activate(KId),
    Plain = <<"sensitive payload data 12345">>,
    {ok, Env} = cb_byok:encrypt(KId, Plain, <<"u">>, <<"model-input">>),
    {ok, Plain} = cb_byok:decrypt(KId, Env, <<"u">>, <<"model-input">>).

byok_rotate_then_decrypt(_) ->
    Key = crypto:strong_rand_bytes(32),
    {ok, KId} = cb_byok:register_key(<<"t">>, Key, <<"AES-256-GCM">>),
    ok = cb_byok:activate(KId),
    {ok, Env} = cb_byok:encrypt(KId, <<"x">>, <<"u">>, <<"p">>),
    ok = cb_byok:rotate(KId, <<"admin">>),
    %% Decrypt should still work for rotated keys
    {ok, <<"x">>} = cb_byok:decrypt(KId, Env, <<"u">>, <<"p">>),
    %% But fresh encrypt should fail
    {error, _} = cb_byok:encrypt(KId, <<"y">>, <<"u">>, <<"p">>).

byok_revoke_blocks_decrypt(_) ->
    Key = crypto:strong_rand_bytes(32),
    {ok, KId} = cb_byok:register_key(<<"t">>, Key, <<"AES-256-GCM">>),
    ok = cb_byok:activate(KId),
    {ok, Env} = cb_byok:encrypt(KId, <<"x">>, <<"u">>, <<"p">>),
    ok = cb_byok:revoke(KId, <<"admin">>),
    {error, _} = cb_byok:decrypt(KId, Env, <<"u">>, <<"p">>).

byok_access_log_records_operations(_) ->
    Key = crypto:strong_rand_bytes(32),
    {ok, KId} = cb_byok:register_key(<<"t">>, Key, <<"AES-256-GCM">>),
    ok = cb_byok:activate(KId),
    {ok, Env} = cb_byok:encrypt(KId, <<"x">>, <<"u">>, <<"p">>),
    {ok, _}   = cb_byok:decrypt(KId, Env, <<"u">>, <<"p">>),
    Logs = cb_byok:list_access_log(KId),
    Ops = [L#byok_access_log.operation || L <- Logs],
    ?assert(lists:member(encrypt, Ops)),
    ?assert(lists:member(decrypt, Ops)).
