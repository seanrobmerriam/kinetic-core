-module(cb_recon_automation_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([
    start_run_ok/1,
    get_run_ok/1,
    get_run_not_found/1,
    list_runs_ok/1,
    complete_run_ok/1,
    fail_run_ok/1,
    record_divergence_ok/1,
    record_divergence_run_not_found/1,
    list_alerts_ok/1,
    list_open_alerts_ok/1,
    acknowledge_alert_ok/1,
    acknowledge_alert_not_found/1,
    acknowledge_alert_already_acknowledged/1
]).

all() ->
    [
        start_run_ok,
        get_run_ok,
        get_run_not_found,
        list_runs_ok,
        complete_run_ok,
        fail_run_ok,
        record_divergence_ok,
        record_divergence_run_not_found,
        list_alerts_ok,
        list_open_alerts_ok,
        acknowledge_alert_ok,
        acknowledge_alert_not_found,
        acknowledge_alert_already_acknowledged
    ].

init_per_suite(Config) ->
    mnesia:start(),
    cb_schema:create_tables(),
    Config.

end_per_suite(_Config) ->
    mnesia:stop(),
    ok.

start_run_ok(_Config) ->
    {ok, RunId} = cb_recon_automation:start_run(<<"ledger_vs_accounts">>),
    ?assert(is_binary(RunId)).

get_run_ok(_Config) ->
    {ok, RunId} = cb_recon_automation:start_run(<<"scope-get">>),
    {ok, R} = cb_recon_automation:get_run(RunId),
    ?assertEqual(RunId, R#recon_run.run_id).

get_run_not_found(_Config) ->
    {error, not_found} = cb_recon_automation:get_run(<<"no-such">>).

list_runs_ok(_Config) ->
    {ok, _} = cb_recon_automation:start_run(<<"scope-list">>),
    All = cb_recon_automation:list_runs(),
    ?assert(length(All) >= 1).

complete_run_ok(_Config) ->
    {ok, RunId} = cb_recon_automation:start_run(<<"scope-complete">>),
    ok = cb_recon_automation:complete_run(RunId),
    {ok, R} = cb_recon_automation:get_run(RunId),
    ?assertEqual(completed, R#recon_run.status).

fail_run_ok(_Config) ->
    {ok, RunId} = cb_recon_automation:start_run(<<"scope-fail">>),
    ok = cb_recon_automation:fail_run(RunId),
    {ok, R} = cb_recon_automation:get_run(RunId),
    ?assertEqual(failed, R#recon_run.status).

record_divergence_ok(_Config) ->
    {ok, RunId} = cb_recon_automation:start_run(<<"scope-div">>),
    {ok, AlertId} = cb_recon_automation:record_divergence(
        RunId, warning, #{expected => 100, actual => 90}),
    ?assert(is_binary(AlertId)),
    {ok, R} = cb_recon_automation:get_run(RunId),
    ?assertEqual(1, R#recon_run.divergences_count).

record_divergence_run_not_found(_Config) ->
    {error, not_found} = cb_recon_automation:record_divergence(
        <<"no-run">>, info, #{}).

list_alerts_ok(_Config) ->
    {ok, RunId} = cb_recon_automation:start_run(<<"scope-list-alerts">>),
    {ok, _} = cb_recon_automation:record_divergence(RunId, info, #{}),
    Alerts = cb_recon_automation:list_alerts(RunId),
    ?assertEqual(1, length(Alerts)).

list_open_alerts_ok(_Config) ->
    {ok, RunId} = cb_recon_automation:start_run(<<"scope-open">>),
    {ok, _} = cb_recon_automation:record_divergence(RunId, critical, #{x => y}),
    Open = cb_recon_automation:list_open_alerts(),
    ?assert(length(Open) >= 1).

acknowledge_alert_ok(_Config) ->
    {ok, RunId} = cb_recon_automation:start_run(<<"scope-ack">>),
    {ok, AlertId} = cb_recon_automation:record_divergence(RunId, info, #{}),
    ok = cb_recon_automation:acknowledge_alert(AlertId, <<"operator-1">>),
    [A] = mnesia:dirty_read(divergence_alert, AlertId),
    ?assertEqual(acknowledged, A#divergence_alert.status),
    ?assertEqual(<<"operator-1">>, A#divergence_alert.acknowledged_by).

acknowledge_alert_not_found(_Config) ->
    {error, not_found} = cb_recon_automation:acknowledge_alert(
        <<"no-alert">>, <<"op">>).

acknowledge_alert_already_acknowledged(_Config) ->
    {ok, RunId} = cb_recon_automation:start_run(<<"scope-ack-twice">>),
    {ok, AlertId} = cb_recon_automation:record_divergence(RunId, info, #{}),
    ok = cb_recon_automation:acknowledge_alert(AlertId, <<"op">>),
    {error, already_acknowledged} =
        cb_recon_automation:acknowledge_alert(AlertId, <<"op">>).
