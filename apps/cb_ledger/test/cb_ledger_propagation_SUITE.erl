-module(cb_ledger_propagation_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([
    register_target_ok/1,
    list_targets_ok/1,
    disable_target_ok/1,
    record_event_ok/1,
    list_events_for_entry_ok/1,
    freshness_no_targets/1,
    freshness_within_sla/1,
    freshness_breached_sla/1
]).

all() ->
    [
        register_target_ok,
        list_targets_ok,
        disable_target_ok,
        record_event_ok,
        list_events_for_entry_ok,
        freshness_no_targets,
        freshness_within_sla,
        freshness_breached_sla
    ].

init_per_suite(Config) ->
    mnesia:start(),
    cb_schema:create_tables(),
    Config.

end_per_suite(_Config) ->
    mnesia:stop(),
    ok.

register_target_ok(_Config) ->
    {ok, Id} = cb_ledger_propagation:register_target(<<"replica-a">>, 250),
    ?assert(is_binary(Id)).

list_targets_ok(_Config) ->
    {ok, _} = cb_ledger_propagation:register_target(<<"replica-list-1">>, 100),
    Targets = cb_ledger_propagation:list_targets(),
    ?assert(length(Targets) >= 1).

disable_target_ok(_Config) ->
    {ok, Id} = cb_ledger_propagation:register_target(<<"replica-disable">>, 500),
    ok = cb_ledger_propagation:disable_target(Id),
    [T] = mnesia:dirty_read(propagation_target, Id),
    ?assertEqual(false, T#propagation_target.enabled).

record_event_ok(_Config) ->
    Posted = erlang:system_time(millisecond),
    {ok, Id} = cb_ledger_propagation:record_propagation(
        <<"entry-001">>, <<"replica-a">>, Posted),
    ?assert(is_binary(Id)).

list_events_for_entry_ok(_Config) ->
    Posted = erlang:system_time(millisecond),
    {ok, _} = cb_ledger_propagation:record_propagation(
        <<"entry-list">>, <<"replica-a">>, Posted),
    Events = cb_ledger_propagation:list_events_for_entry(<<"entry-list">>),
    ?assert(length(Events) >= 1).

freshness_no_targets(_Config) ->
    %% Disable any pre-existing enabled targets so this test sees no targets.
    lists:foreach(
        fun(T) ->
            cb_ledger_propagation:disable_target(T#propagation_target.target_id)
        end,
        cb_ledger_propagation:list_targets()),
    {ok, R} = cb_ledger_propagation:freshness(<<"any-entry">>),
    %% No enabled targets ⇒ vacuously fresh.
    ?assertEqual(true, maps:get(fresh, R)).

freshness_within_sla(_Config) ->
    {ok, _} = cb_ledger_propagation:register_target(<<"replica-fresh">>, 60000),
    Posted = erlang:system_time(millisecond),
    {ok, _} = cb_ledger_propagation:record_propagation(
        <<"entry-fresh">>, <<"replica-fresh">>, Posted),
    {ok, R} = cb_ledger_propagation:freshness(<<"entry-fresh">>),
    ?assertEqual(true, maps:get(fresh, R)).

freshness_breached_sla(_Config) ->
    {ok, _} = cb_ledger_propagation:register_target(<<"replica-strict">>, 0),
    Posted = erlang:system_time(millisecond) - 1000,
    {ok, _} = cb_ledger_propagation:record_propagation(
        <<"entry-stale">>, <<"replica-strict">>, Posted),
    {ok, R} = cb_ledger_propagation:freshness(<<"entry-stale">>),
    ?assertEqual(false, maps:get(fresh, R)).
