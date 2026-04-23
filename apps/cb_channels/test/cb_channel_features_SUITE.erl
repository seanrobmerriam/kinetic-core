-module(cb_channel_features_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    set_flag_creates_entry/1,
    set_flag_updates_existing/1,
    get_flag_returns_not_found/1,
    get_flag_returns_value/1,
    is_enabled_true_when_set/1,
    is_enabled_false_when_not_set/1,
    list_for_channel_returns_all/1
]).

all() ->
    [
        set_flag_creates_entry,
        set_flag_updates_existing,
        get_flag_returns_not_found,
        get_flag_returns_value,
        is_enabled_true_when_set,
        is_enabled_false_when_not_set,
        list_for_channel_returns_all
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
    mnesia:clear_table(channel_feature_flag),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

set_flag_creates_entry(_Config) ->
    {ok, Flag} = cb_channel_features:set_flag(web, <<"fast_payments">>, true),
    ?assertEqual(web, Flag#channel_feature_flag.channel),
    ?assertEqual(<<"fast_payments">>, Flag#channel_feature_flag.feature),
    ?assertEqual(true, Flag#channel_feature_flag.enabled).

set_flag_updates_existing(_Config) ->
    {ok, _} = cb_channel_features:set_flag(mobile, <<"biometrics">>, true),
    {ok, Updated} = cb_channel_features:set_flag(mobile, <<"biometrics">>, false),
    ?assertEqual(false, Updated#channel_feature_flag.enabled).

get_flag_returns_not_found(_Config) ->
    ?assertEqual({error, not_found}, cb_channel_features:get_flag(atm, <<"unknown">>)).

get_flag_returns_value(_Config) ->
    {ok, _} = cb_channel_features:set_flag(branch, <<"loan_origination">>, true),
    {ok, Flag} = cb_channel_features:get_flag(branch, <<"loan_origination">>),
    ?assertEqual(true, Flag#channel_feature_flag.enabled).

is_enabled_true_when_set(_Config) ->
    {ok, _} = cb_channel_features:set_flag(web, <<"instant_transfer">>, true),
    ?assertEqual(true, cb_channel_features:is_enabled(web, <<"instant_transfer">>)).

is_enabled_false_when_not_set(_Config) ->
    ?assertEqual(false, cb_channel_features:is_enabled(web, <<"nonexistent_feature">>)).

list_for_channel_returns_all(_Config) ->
    {ok, _} = cb_channel_features:set_flag(mobile, <<"feature_a">>, true),
    {ok, _} = cb_channel_features:set_flag(mobile, <<"feature_b">>, false),
    {ok, Flags} = cb_channel_features:list_for_channel(mobile),
    ?assertEqual(2, length(Flags)).
