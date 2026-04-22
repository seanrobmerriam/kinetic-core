%% @doc Currency precision and conversion engine.
%%
%% Manages ISO 4217 currency definitions and provides amount conversion
%% between currencies using stored exchange rates.
%%
%% All amounts are in minor units (integer). Conversion uses rates from
%% cb_fx_rates, stored as integer millionths (rate_millionths / 1_000_000).
-module(cb_currency).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    seed_defaults/0,
    get_precision/1,
    valid_currency/1,
    convert_amount/3,
    list_currencies/0,
    get_currency/1
]).

%% Default precision digits per ISO 4217.
-define(DEFAULT_CONFIGS, [
    {'USD', 2, <<"US Dollar">>},
    {'EUR', 2, <<"Euro">>},
    {'GBP', 2, <<"British Pound">>},
    {'JPY', 0, <<"Japanese Yen">>},
    {'CHF', 2, <<"Swiss Franc">>},
    {'AUD', 2, <<"Australian Dollar">>},
    {'CAD', 2, <<"Canadian Dollar">>},
    {'SGD', 2, <<"Singapore Dollar">>},
    {'HKD', 2, <<"Hong Kong Dollar">>},
    {'NZD', 2, <<"New Zealand Dollar">>}
]).

%% @doc Seed default currency configurations into Mnesia.
-spec seed_defaults() -> ok.
seed_defaults() ->
    Now = erlang:system_time(millisecond),
    lists:foreach(fun({Code, Precision, Desc}) ->
        Record = #currency_config{
            currency_code    = Code,
            precision_digits = Precision,
            description      = Desc,
            is_active        = true,
            created_at       = Now
        },
        mnesia:dirty_write(currency_config, Record)
    end, ?DEFAULT_CONFIGS),
    ok.

%% @doc Get precision digits for a currency code.
-spec get_precision(currency()) -> {ok, non_neg_integer()} | {error, unknown_currency}.
get_precision(Code) ->
    case mnesia:dirty_read(currency_config, Code) of
        [#currency_config{precision_digits = P}] -> {ok, P};
        [] -> {error, unknown_currency}
    end.

%% @doc Validate that a currency code is known and active.
-spec valid_currency(currency()) -> boolean().
valid_currency(Code) ->
    case mnesia:dirty_read(currency_config, Code) of
        [#currency_config{is_active = true}] -> true;
        _ -> false
    end.

%% @doc Convert an amount from one currency to another using latest exchange rate.
%%
%% Returns the converted amount in the destination currency's minor units.
%% Uses the most recent rate from cb_fx_rates.
-spec convert_amount(amount(), currency(), currency()) ->
    {ok, amount()} | {error, no_rate | same_currency | unknown_currency}.
convert_amount(_Amount, Same, Same) ->
    {error, same_currency};
convert_amount(Amount, FromCurrency, ToCurrency) ->
    case {valid_currency(FromCurrency), valid_currency(ToCurrency)} of
        {false, _} -> {error, unknown_currency};
        {_, false} -> {error, unknown_currency};
        {true, true} ->
            case cb_fx_rates:get_rate(FromCurrency, ToCurrency) of
                {ok, RateMillionths} ->
                    Converted = (Amount * RateMillionths) div 1_000_000,
                    {ok, Converted};
                {error, no_rate} ->
                    {error, no_rate}
            end
    end.

%% @doc List all active currency configurations.
-dialyzer({nowarn_function, list_currencies/0}).
-spec list_currencies() -> [#currency_config{}].
list_currencies() ->
    Records = mnesia:dirty_match_object(currency_config, #currency_config{_ = '_'}),
    [R || R <- Records, R#currency_config.is_active =:= true].

%% @doc Get a single currency configuration by code.
-spec get_currency(currency()) -> {ok, #currency_config{}} | {error, not_found}.
get_currency(Code) ->
    case mnesia:dirty_read(currency_config, Code) of
        [Config] -> {ok, Config};
        [] -> {error, not_found}
    end.
