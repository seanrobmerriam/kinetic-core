-module(cb_fx_rates_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    set_rate_ok/1,
    set_rate_same_currency/1,
    set_rate_invalid_rate/1,
    get_rate_ok/1,
    get_rate_no_rate/1,
    get_rate_returns_latest/1,
    get_rate_at_historical/1,
    get_rate_at_same_currency/1,
    list_rates/1,
    list_rates_for_pair/1
]).

all() ->
    [
        set_rate_ok,
        set_rate_same_currency,
        set_rate_invalid_rate,
        get_rate_ok,
        get_rate_no_rate,
        get_rate_returns_latest,
        get_rate_at_historical,
        get_rate_at_same_currency,
        list_rates,
        list_rates_for_pair
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
    mnesia:clear_table(exchange_rate),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

set_rate_ok(_Config) ->
    {ok, Rate} = cb_fx_rates:set_rate('USD', 'EUR', 920_000),
    ?assertEqual('USD', Rate#exchange_rate.from_currency),
    ?assertEqual('EUR', Rate#exchange_rate.to_currency),
    ?assertEqual(920_000, Rate#exchange_rate.rate_millionths),
    ok.

set_rate_same_currency(_Config) ->
    {error, same_currency} = cb_fx_rates:set_rate('USD', 'USD', 1_000_000),
    ok.

set_rate_invalid_rate(_Config) ->
    {error, invalid_rate} = cb_fx_rates:set_rate('USD', 'EUR', 0),
    ok.

get_rate_ok(_Config) ->
    {ok, _} = cb_fx_rates:set_rate('USD', 'EUR', 920_000),
    {ok, 920_000} = cb_fx_rates:get_rate('USD', 'EUR'),
    ok.

get_rate_no_rate(_Config) ->
    {error, no_rate} = cb_fx_rates:get_rate('GBP', 'JPY'),
    ok.

get_rate_returns_latest(_Config) ->
    {ok, _} = cb_fx_rates:set_rate('USD', 'EUR', 900_000),
    timer:sleep(2),
    {ok, _} = cb_fx_rates:set_rate('USD', 'EUR', 950_000),
    {ok, 950_000} = cb_fx_rates:get_rate('USD', 'EUR'),
    ok.

get_rate_at_historical(_Config) ->
    {ok, _} = cb_fx_rates:set_rate('USD', 'EUR', 900_000),
    T1 = erlang:system_time(millisecond),
    timer:sleep(2),
    {ok, _} = cb_fx_rates:set_rate('USD', 'EUR', 950_000),
    {ok, 900_000} = cb_fx_rates:get_rate_at('USD', 'EUR', T1),
    ok.

get_rate_at_same_currency(_Config) ->
    {error, same_currency} = cb_fx_rates:get_rate_at('USD', 'USD', 0),
    ok.

list_rates(_Config) ->
    {ok, _} = cb_fx_rates:set_rate('USD', 'EUR', 920_000),
    {ok, _} = cb_fx_rates:set_rate('EUR', 'GBP', 860_000),
    Rates = cb_fx_rates:list_rates(),
    ?assertEqual(2, length(Rates)),
    ok.

list_rates_for_pair(_Config) ->
    {ok, _} = cb_fx_rates:set_rate('USD', 'EUR', 920_000),
    {ok, _} = cb_fx_rates:set_rate('USD', 'EUR', 930_000),
    {ok, _} = cb_fx_rates:set_rate('USD', 'GBP', 790_000),
    Rates = cb_fx_rates:list_rates_for_pair('USD', 'EUR'),
    ?assertEqual(2, length(Rates)),
    ok.
