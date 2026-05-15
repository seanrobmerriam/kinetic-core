%% @doc Currency pair spread configuration management.
%%
%% Manages currency pairs with configurable buy/sell spreads for FX operations.
%% Each pair has a base exchange rate and a spread percentage that determines
%% the buy and sell prices offered to customers.
%%
%% Spread is stored as an integer in millionths (basis points).
%% Example: spread_millionths = 5000 means 0.5% spread (50 basis points).
-module(cb_currency_pair).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    create_pair/4,
    get_pair/1,
    list_pairs/0,
    update_pair/2,
    get_spread/2
]).

-define(TABLE, currency_pair).

%% @doc Create a new currency pair with spread configuration.
%%
%% @param FromCurrency The base/quote currency (e.g., USD)
%% @param ToCurrency   The target currency (e.g., EUR)
%% @param SpreadMillionths Spread in millionths (0 = no spread, 5000 = 0.5%)
-spec create_pair(currency(), currency(), pos_integer(), currency()) ->
    {ok, #currency_pair{}} | {error, same_currency | invalid_spread | pair_exists}.
create_pair(Same, Same, _Spread, _SettlementCurrency) ->
    {error, same_currency};
create_pair(_From, _To, Spread, _SettlementCurrency) when Spread < 0 ->
    {error, invalid_spread};
create_pair(FromCurrency, ToCurrency, SpreadMillionths, SettlementCurrency) ->
    case get_pair({FromCurrency, ToCurrency}) of
        {ok, _} -> {error, pair_exists};
        {error, not_found} ->
            PairId = <<(atom_to_binary(FromCurrency, utf8))/binary, $/,
                       (atom_to_binary(ToCurrency, utf8))/binary>>,
            Now = erlang:system_time(millisecond),
            Record = #currency_pair{
                pair_id              = PairId,
                from_currency        = FromCurrency,
                to_currency          = ToCurrency,
                spread_millionths    = SpreadMillionths,
                settlement_currency  = SettlementCurrency,
                created_at           = Now,
                updated_at           = Now
            },
            F = fun() -> mnesia:write(?TABLE, Record, write) end,
            case mnesia:transaction(F) of
                {atomic, ok} -> {ok, Record};
                {aborted, Reason} -> {error, Reason}
            end
    end.

%% @doc Get a currency pair by its pair ID.
-spec get_pair(binary()) -> {ok, #currency_pair{}} | {error, not_found}.
get_pair(PairId) when is_binary(PairId) ->
    case mnesia:dirty_read(?TABLE, PairId) of
        [] -> {error, not_found};
        [Pair] -> {ok, Pair}
    end.

%% @doc List all configured currency pairs.
-spec list_pairs() -> [#currency_pair{}].
list_pairs() ->
    mnesia:dirty_match_object(?TABLE, #currency_pair{_ = '_'}).

%% @doc Update spread and/or settlement currency for a pair.
-spec update_pair(binary(), map()) ->
    {ok, #currency_pair{}} | {error, not_found | invalid_spread}.
update_pair(PairId, Updates) when is_binary(PairId) ->
    case mnesia:dirty_read(?TABLE, PairId) of
        [] -> {error, not_found};
        [Pair] ->
            NewSpread = maps:get(spread_millionths, Updates, Pair#currency_pair.spread_millionths),
            NewSettlement = maps:get(settlement_currency, Updates, Pair#currency_pair.settlement_currency),
            case NewSpread < 0 of
                true -> {error, invalid_spread};
                false ->
                    UpdatedPair = Pair#currency_pair{
                        spread_millionths   = NewSpread,
                        settlement_currency = NewSettlement,
                        updated_at          = erlang:system_time(millisecond)
                    },
                    F = fun() -> mnesia:write(?TABLE, UpdatedPair, write) end,
                    case mnesia:transaction(F) of
                        {atomic, ok} -> {ok, UpdatedPair};
                        {aborted, Reason} -> {error, Reason}
                    end
            end
    end.

%% @doc Get the spread in millionths for a currency pair.
-spec get_spread(currency(), currency()) -> {ok, pos_integer()} | {error, not_found}.
get_spread(FromCurrency, ToCurrency) ->
    PairId = <<(atom_to_binary(FromCurrency, utf8))/binary, $/,
               (atom_to_binary(ToCurrency, utf8))/binary>>,
    case get_pair(PairId) of
        {ok, Pair} -> {ok, Pair#currency_pair.spread_millionths};
        {error, _} = Err -> Err
    end.