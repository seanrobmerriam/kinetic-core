-module(cb_channel_limits_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    get_limits_returns_default_unlimited/1,
    set_limits_stores_values/1,
    set_limits_invalid_values/1,
    validate_amount_within_limit/1,
    validate_amount_exceeds_limit/1,
    validate_amount_unlimited/1,
    validate_amount_zero/1,
    list_all_returns_all_limits/1
]).

all() ->
    [
        get_limits_returns_default_unlimited,
        set_limits_stores_values,
        set_limits_invalid_values,
        validate_amount_within_limit,
        validate_amount_exceeds_limit,
        validate_amount_unlimited,
        validate_amount_zero,
        list_all_returns_all_limits
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
    mnesia:clear_table(channel_limit),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

get_limits_returns_default_unlimited(_Config) ->
    {ok, Limit} = cb_channel_limits:get_limits(web, 'USD'),
    ?assertEqual({web, 'USD'}, Limit#channel_limit.limit_key),
    ?assertEqual(0, Limit#channel_limit.daily_limit),
    ?assertEqual(0, Limit#channel_limit.per_txn_limit).

set_limits_stores_values(_Config) ->
    {ok, Limit} = cb_channel_limits:set_limits(mobile, 'EUR', 500000, 100000),
    ?assertEqual({mobile, 'EUR'}, Limit#channel_limit.limit_key),
    ?assertEqual(500000, Limit#channel_limit.daily_limit),
    ?assertEqual(100000, Limit#channel_limit.per_txn_limit),
    {ok, Read} = cb_channel_limits:get_limits(mobile, 'EUR'),
    ?assertEqual(100000, Read#channel_limit.per_txn_limit).

set_limits_invalid_values(_Config) ->
    ?assertEqual({error, invalid_limit_value}, cb_channel_limits:set_limits(web, 'USD', -1, 0)),
    ?assertEqual({error, invalid_limit_value}, cb_channel_limits:set_limits(web, 'USD', 0, -1)).

validate_amount_within_limit(_Config) ->
    {ok, _} = cb_channel_limits:set_limits(atm, 'USD', 1000000, 200000),
    ?assertEqual(ok, cb_channel_limits:validate_amount(atm, 'USD', 150000)).

validate_amount_exceeds_limit(_Config) ->
    {ok, _} = cb_channel_limits:set_limits(atm, 'GBP', 1000000, 50000),
    ?assertEqual({error, per_txn_limit_exceeded}, cb_channel_limits:validate_amount(atm, 'GBP', 100000)).

validate_amount_unlimited(_Config) ->
    %% Default limit is 0 (unlimited); any positive amount should pass
    ?assertEqual(ok, cb_channel_limits:validate_amount(branch, 'USD', 99999999)).

validate_amount_zero(_Config) ->
    ?assertEqual({error, invalid_amount}, cb_channel_limits:validate_amount(web, 'USD', 0)).

list_all_returns_all_limits(_Config) ->
    {ok, _} = cb_channel_limits:set_limits(web,    'USD', 1000000, 100000),
    {ok, _} = cb_channel_limits:set_limits(mobile, 'USD', 500000,  50000),
    All = cb_channel_limits:list_all(),
    ?assertEqual(2, length(All)).
