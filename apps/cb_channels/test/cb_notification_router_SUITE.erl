-module(cb_notification_router_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    dispatch_returns_empty_when_no_prefs/1,
    dispatch_routes_to_enabled_channel/1,
    dispatch_skips_disabled_channels/1,
    dispatch_skips_non_matching_event_types/1
]).

all() ->
    [
        dispatch_returns_empty_when_no_prefs,
        dispatch_routes_to_enabled_channel,
        dispatch_skips_disabled_channels,
        dispatch_skips_non_matching_event_types
    ].

init_per_suite(Config) ->
    mnesia:start(),
    cb_schema:create_tables(),
    Config.

end_per_suite(_Config) ->
    mnesia:stop(),
    mnesia:delete_schema([node()]),
    ok.

init_per_testcase(_TestCase, Config) ->
    mnesia:clear_table(notification_preference),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

dispatch_returns_empty_when_no_prefs(_Config) ->
    {ok, Channels} = cb_notification_router:dispatch(<<"unknown-party">>, <<"txn.posted">>, #{}),
    ?assertEqual([], Channels).

dispatch_routes_to_enabled_channel(_Config) ->
    {ok, _} = cb_notification_prefs:set_pref(<<"party-1">>, email, [<<"txn.posted">>], true),
    {ok, Channels} = cb_notification_router:dispatch(<<"party-1">>, <<"txn.posted">>, #{}),
    ?assertEqual([email], Channels).

dispatch_skips_disabled_channels(_Config) ->
    {ok, _} = cb_notification_prefs:set_pref(<<"party-2">>, sms, [<<"txn.posted">>], false),
    {ok, Channels} = cb_notification_router:dispatch(<<"party-2">>, <<"txn.posted">>, #{}),
    ?assertEqual([], Channels).

dispatch_skips_non_matching_event_types(_Config) ->
    {ok, _} = cb_notification_prefs:set_pref(<<"party-3">>, push, [<<"balance.low">>], true),
    {ok, Channels} = cb_notification_router:dispatch(<<"party-3">>, <<"txn.posted">>, #{}),
    ?assertEqual([], Channels).
