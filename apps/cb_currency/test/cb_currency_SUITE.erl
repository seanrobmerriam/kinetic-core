-module(cb_currency_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    precision_usd/1,
    precision_jpy/1,
    precision_unknown/1,
    valid_currency_ok/1,
    valid_currency_unknown/1,
    convert_amount_ok/1,
    convert_amount_same_currency/1,
    convert_amount_no_rate/1,
    list_currencies_ok/1,
    get_currency_ok/1,
    get_currency_not_found/1
]).

all() ->
    [
        precision_usd,
        precision_jpy,
        precision_unknown,
        valid_currency_ok,
        valid_currency_unknown,
        convert_amount_ok,
        convert_amount_same_currency,
        convert_amount_no_rate,
        list_currencies_ok,
        get_currency_ok,
        get_currency_not_found
    ].

init_per_suite(Config) ->
    mnesia:start(),
    cb_schema:create_tables(),
    cb_currency:seed_defaults(),
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

precision_usd(_Config) ->
    {ok, 2} = cb_currency:get_precision('USD'),
    ok.

precision_jpy(_Config) ->
    {ok, 0} = cb_currency:get_precision('JPY'),
    ok.

precision_unknown(_Config) ->
    {error, unknown_currency} = cb_currency:get_precision('XXX'),
    ok.

valid_currency_ok(_Config) ->
    ?assert(cb_currency:valid_currency('EUR')),
    ok.

valid_currency_unknown(_Config) ->
    ?assertNot(cb_currency:valid_currency('XYZ')),
    ok.

convert_amount_ok(_Config) ->
    {ok, _} = cb_fx_rates:set_rate('USD', 'EUR', 920_000),
    {ok, Converted} = cb_currency:convert_amount(10000, 'USD', 'EUR'),
    ?assertEqual(9200, Converted),
    ok.

convert_amount_same_currency(_Config) ->
    {error, same_currency} = cb_currency:convert_amount(1000, 'USD', 'USD'),
    ok.

convert_amount_no_rate(_Config) ->
    {error, no_rate} = cb_currency:convert_amount(1000, 'USD', 'GBP'),
    ok.

list_currencies_ok(_Config) ->
    Currencies = cb_currency:list_currencies(),
    ?assert(length(Currencies) >= 10),
    ok.

get_currency_ok(_Config) ->
    {ok, Config} = cb_currency:get_currency('USD'),
    ?assertEqual('USD', Config#currency_config.currency_code),
    ?assertEqual(2, Config#currency_config.precision_digits),
    ok.

get_currency_not_found(_Config) ->
    {error, not_found} = cb_currency:get_currency('ZZZ'),
    ok.
