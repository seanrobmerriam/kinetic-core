-module(cb_notification_prefs_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    set_pref_creates_new/1,
    set_pref_updates_same_id/1,
    get_pref_returns_not_found/1,
    get_pref_returns_value/1,
    list_for_party_returns_all/1
]).

all() ->
    [
        set_pref_creates_new,
        set_pref_updates_same_id,
        get_pref_returns_not_found,
        get_pref_returns_value,
        list_for_party_returns_all
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

set_pref_creates_new(_Config) ->
    {ok, Pref} = cb_notification_prefs:set_pref(<<"party-1">>, email, [<<"transaction_alert">>], true),
    ?assertEqual(<<"party-1">>, Pref#notification_preference.party_id),
    ?assertEqual(email, Pref#notification_preference.channel),
    ?assertEqual([<<"transaction_alert">>], Pref#notification_preference.event_types),
    ?assertEqual(true, Pref#notification_preference.enabled).

set_pref_updates_same_id(_Config) ->
    {ok, Pref1} = cb_notification_prefs:set_pref(<<"party-2">>, sms, [<<"balance_alert">>], true),
    {ok, Pref2} = cb_notification_prefs:set_pref(<<"party-2">>, sms, [<<"balance_alert">>], false),
    ?assertEqual(Pref1#notification_preference.pref_id, Pref2#notification_preference.pref_id),
    ?assertEqual(false, Pref2#notification_preference.enabled).

get_pref_returns_not_found(_Config) ->
    ?assertEqual({error, not_found}, cb_notification_prefs:get_pref(<<"no-such-party">>, email)).

get_pref_returns_value(_Config) ->
    {ok, _} = cb_notification_prefs:set_pref(<<"party-3">>, push, [<<"login_alert">>], true),
    {ok, Pref} = cb_notification_prefs:get_pref(<<"party-3">>, push),
    ?assertEqual(push, Pref#notification_preference.channel),
    ?assertEqual([<<"login_alert">>], Pref#notification_preference.event_types).

list_for_party_returns_all(_Config) ->
    {ok, _} = cb_notification_prefs:set_pref(<<"party-4">>, email, [<<"transaction_alert">>], true),
    {ok, _} = cb_notification_prefs:set_pref(<<"party-4">>, sms,   [<<"balance_alert">>],     false),
    {ok, _} = cb_notification_prefs:set_pref(<<"party-5">>, email, [<<"login_alert">>],       true),
    Prefs4 = cb_notification_prefs:list_for_party(<<"party-4">>),
    ?assertEqual(2, length(Prefs4)).
