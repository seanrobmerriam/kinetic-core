-module(cb_ledger_replay_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([
    start_session_ok/1,
    start_session_invalid_window/1,
    get_session_ok/1,
    get_session_not_found/1,
    list_sessions_ok/1,
    record_event_ok/1,
    record_event_session_not_found/1,
    record_event_invalid_status/1,
    list_events_ok/1,
    complete_session_ok/1,
    fail_session_ok/1,
    abort_session_ok/1
]).

all() ->
    [
        start_session_ok,
        start_session_invalid_window,
        get_session_ok,
        get_session_not_found,
        list_sessions_ok,
        record_event_ok,
        record_event_session_not_found,
        record_event_invalid_status,
        list_events_ok,
        complete_session_ok,
        fail_session_ok,
        abort_session_ok
    ].

init_per_suite(Config) ->
    mnesia:start(),
    cb_schema:create_tables(),
    Config.

end_per_suite(_Config) ->
    mnesia:stop(),
    ok.

start_session_ok(_Config) ->
    {ok, SessionId} = cb_ledger_replay:start_session(
        <<"all-entries">>, 0, erlang:system_time(millisecond)),
    ?assert(is_binary(SessionId)).

start_session_invalid_window(_Config) ->
    {error, invalid_window} = cb_ledger_replay:start_session(
        <<"bad">>, 100, 50).

get_session_ok(_Config) ->
    {ok, SessionId} = cb_ledger_replay:start_session(<<"scope-get">>, 0, 1),
    {ok, S} = cb_ledger_replay:get_session(SessionId),
    ?assertEqual(SessionId, S#replay_session.session_id).

get_session_not_found(_Config) ->
    {error, not_found} = cb_ledger_replay:get_session(<<"no-session">>).

list_sessions_ok(_Config) ->
    {ok, _} = cb_ledger_replay:start_session(<<"scope-list">>, 0, 1),
    All = cb_ledger_replay:list_sessions(),
    ?assert(length(All) >= 1).

record_event_ok(_Config) ->
    {ok, SessionId} = cb_ledger_replay:start_session(<<"scope-rec">>, 0, 1),
    {ok, EventId} = cb_ledger_replay:record_event(
        SessionId, <<"entry-1">>, ok, undefined),
    ?assert(is_binary(EventId)),
    {ok, S} = cb_ledger_replay:get_session(SessionId),
    ?assertEqual(1, S#replay_session.applied_count).

record_event_session_not_found(_Config) ->
    {error, not_found} = cb_ledger_replay:record_event(
        <<"no-session">>, <<"entry-x">>, ok, undefined).

record_event_invalid_status(_Config) ->
    {ok, SessionId} = cb_ledger_replay:start_session(<<"scope-bad-status">>, 0, 1),
    ok = cb_ledger_replay:complete_session(SessionId),
    {error, invalid_status} = cb_ledger_replay:record_event(
        SessionId, <<"entry-y">>, ok, undefined).

list_events_ok(_Config) ->
    {ok, SessionId} = cb_ledger_replay:start_session(<<"scope-events">>, 0, 1),
    {ok, _} = cb_ledger_replay:record_event(SessionId, <<"e1">>, ok, undefined),
    {ok, _} = cb_ledger_replay:record_event(SessionId, <<"e2">>, skipped, <<"dup">>),
    Events = cb_ledger_replay:list_events(SessionId),
    ?assertEqual(2, length(Events)).

complete_session_ok(_Config) ->
    {ok, SessionId} = cb_ledger_replay:start_session(<<"scope-complete">>, 0, 1),
    ok = cb_ledger_replay:complete_session(SessionId),
    {ok, S} = cb_ledger_replay:get_session(SessionId),
    ?assertEqual(completed, S#replay_session.status).

fail_session_ok(_Config) ->
    {ok, SessionId} = cb_ledger_replay:start_session(<<"scope-fail">>, 0, 1),
    ok = cb_ledger_replay:fail_session(SessionId, <<"boom">>),
    {ok, S} = cb_ledger_replay:get_session(SessionId),
    ?assertEqual(failed, S#replay_session.status),
    ?assertEqual(<<"boom">>, S#replay_session.last_error).

abort_session_ok(_Config) ->
    {ok, SessionId} = cb_ledger_replay:start_session(<<"scope-abort">>, 0, 1),
    ok = cb_ledger_replay:abort_session(SessionId),
    {ok, S} = cb_ledger_replay:get_session(SessionId),
    ?assertEqual(aborted, S#replay_session.status).
