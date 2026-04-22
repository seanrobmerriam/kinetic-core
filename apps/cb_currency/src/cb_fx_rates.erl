%% @doc Exchange rate management with historical lookup support.
%%
%% Exchange rates are stored as integer millionths. A rate of 1_000_000
%% means 1:1 parity. A rate of 920_000 means 0.92 (e.g., USD to EUR).
%%
%% Multiple rate records can exist for the same currency pair.
%% get_rate/2 returns the most recent active rate.
%% get_rate_at/3 returns the rate that was valid at a given timestamp.
-module(cb_fx_rates).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    set_rate/3,
    get_rate/2,
    get_rate_at/3,
    list_rates/0,
    list_rates_for_pair/2
]).

%% @doc Store a new exchange rate for a currency pair.
%%
%% Each call creates a new historical record. Rate is in millionths.
%% Example: set_rate('USD', 'EUR', 920_000) stores rate of 0.920000.
-spec set_rate(currency(), currency(), pos_integer()) ->
    {ok, #exchange_rate{}} | {error, same_currency | invalid_rate}.
set_rate(Same, Same, _) ->
    {error, same_currency};
set_rate(_From, _To, Rate) when Rate =< 0 ->
    {error, invalid_rate};
set_rate(FromCurrency, ToCurrency, RateMillionths) ->
    RateId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
    Now = erlang:system_time(millisecond),
    Record = #exchange_rate{
        rate_id         = RateId,
        from_currency   = FromCurrency,
        to_currency     = ToCurrency,
        rate_millionths = RateMillionths,
        recorded_at     = Now
    },
    F = fun() -> mnesia:write(exchange_rate, Record, write) end,
    case mnesia:transaction(F) of
        {atomic, ok} -> {ok, Record};
        {aborted, Reason} -> {error, Reason}
    end.

%% @doc Get the latest exchange rate for a currency pair.
-spec get_rate(currency(), currency()) ->
    {ok, pos_integer()} | {error, no_rate | same_currency}.
get_rate(Same, Same) ->
    {error, same_currency};
get_rate(FromCurrency, ToCurrency) ->
    Rates = mnesia:dirty_index_read(exchange_rate, FromCurrency, from_currency),
    Matching = [R || R <- Rates, R#exchange_rate.to_currency =:= ToCurrency],
    case Matching of
        [] -> {error, no_rate};
        _ ->
            Latest = lists:last(lists:keysort(#exchange_rate.recorded_at, Matching)),
            {ok, Latest#exchange_rate.rate_millionths}
    end.

%% @doc Get the exchange rate that was valid at or before a given timestamp.
-spec get_rate_at(currency(), currency(), timestamp_ms()) ->
    {ok, pos_integer()} | {error, no_rate | same_currency}.
get_rate_at(Same, Same, _At) ->
    {error, same_currency};
get_rate_at(FromCurrency, ToCurrency, At) ->
    Rates = mnesia:dirty_index_read(exchange_rate, FromCurrency, from_currency),
    Matching = [R || R <- Rates,
                     R#exchange_rate.to_currency =:= ToCurrency,
                     R#exchange_rate.recorded_at =< At],
    case Matching of
        [] -> {error, no_rate};
        _ ->
            Latest = lists:last(lists:keysort(#exchange_rate.recorded_at, Matching)),
            {ok, Latest#exchange_rate.rate_millionths}
    end.

%% @doc List all exchange rate records.
-dialyzer({nowarn_function, list_rates/0}).
-spec list_rates() -> [#exchange_rate{}].
list_rates() ->
    mnesia:dirty_match_object(exchange_rate, #exchange_rate{_ = '_'}).

%% @doc List all exchange rate records for a specific currency pair.
-spec list_rates_for_pair(currency(), currency()) -> [#exchange_rate{}].
list_rates_for_pair(FromCurrency, ToCurrency) ->
    Rates = mnesia:dirty_index_read(exchange_rate, FromCurrency, from_currency),
    [R || R <- Rates, R#exchange_rate.to_currency =:= ToCurrency].
