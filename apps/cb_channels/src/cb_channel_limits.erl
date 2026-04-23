%% @doc Channel-specific transaction limit management.
%%
%% Stores and enforces per-channel, per-currency transaction limits:
%% - per_txn_limit: Maximum amount for a single transaction (0 = unlimited)
%% - daily_limit: Maximum cumulative volume in a 24-hour window (0 = unlimited)
%%
%% Limits are keyed by {channel_type, currency}. Default: unlimited (0).
-module(cb_channel_limits).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    get_limits/2,
    set_limits/4,
    validate_amount/3,
    validate_daily_volume/3,
    list_all/0
]).

%% @doc Get the configured limit for a channel + currency pair.
%%
%% Returns the stored record, or a default unlimited record if not configured.
-spec get_limits(channel_type(), currency()) ->
    {ok, #channel_limit{}}.
get_limits(Channel, Currency) ->
    Key = {Channel, Currency},
    case mnesia:dirty_read(channel_limit, Key) of
        [Limit] ->
            {ok, Limit};
        [] ->
            Now = erlang:system_time(millisecond),
            Default = #channel_limit{
                limit_key     = Key,
                daily_limit   = 0,
                per_txn_limit = 0,
                updated_at    = Now
            },
            {ok, Default}
    end.

%% @doc Set or replace the limit for a channel + currency pair.
%%
%% DailyLimit and PerTxnLimit are in minor units. Use 0 for unlimited.
-spec set_limits(channel_type(), currency(), non_neg_integer(), non_neg_integer()) ->
    {ok, #channel_limit{}} | {error, atom()}.
set_limits(Channel, Currency, DailyLimit, PerTxnLimit)
        when is_integer(DailyLimit), DailyLimit >= 0,
             is_integer(PerTxnLimit), PerTxnLimit >= 0 ->
    Now = erlang:system_time(millisecond),
    Limit = #channel_limit{
        limit_key     = {Channel, Currency},
        daily_limit   = DailyLimit,
        per_txn_limit = PerTxnLimit,
        updated_at    = Now
    },
    F = fun() -> mnesia:write(Limit) end,
    case mnesia:transaction(F) of
        {atomic, ok}        -> {ok, Limit};
        {aborted, _Reason}  -> {error, database_error}
    end;
set_limits(_, _, _, _) ->
    {error, invalid_limit_value}.

%% @doc Validate a transaction amount against channel limits.
%%
%% Returns ok if the amount is within limits, or {error, Reason} if not.
%% A limit of 0 means unlimited.
-spec validate_amount(channel_type(), currency(), pos_integer()) ->
    ok | {error, per_txn_limit_exceeded | invalid_amount}.
validate_amount(_Channel, _Currency, Amount) when Amount =< 0 ->
    {error, invalid_amount};
validate_amount(Channel, Currency, Amount) ->
    {ok, Limit} = get_limits(Channel, Currency),
    PerTxn = Limit#channel_limit.per_txn_limit,
    case PerTxn > 0 andalso Amount > PerTxn of
        true  -> {error, per_txn_limit_exceeded};
        false -> ok
    end.

%% @doc Validate that a new transaction amount does not exceed the rolling
%% 24-hour daily volume limit for the given channel and currency.
%%
%% A daily_limit of 0 means unlimited and the check is skipped.
%% The rolling window is the 24 hours prior to the current time.
-dialyzer({nowarn_function, validate_daily_volume/3}).
-spec validate_daily_volume(channel_type(), currency(), pos_integer()) ->
    ok | {error, daily_limit_exceeded}.
validate_daily_volume(Channel, Currency, NewAmount) ->
    {ok, Limit} = get_limits(Channel, Currency),
    DailyLimit = Limit#channel_limit.daily_limit,
    case DailyLimit > 0 of
        false ->
            ok;
        true ->
            ChannelBin   = atom_to_binary(Channel, utf8),
            WindowStart  = erlang:system_time(millisecond) - (24 * 3600 * 1000),
            All          = mnesia:dirty_match_object(#transaction{_ = '_'}),
            Volume = lists:foldl(fun(T, Acc) ->
                Matches =
                    (T#transaction.currency =:= Currency) andalso
                    (T#transaction.status =/= failed) andalso
                    (T#transaction.created_at >= WindowStart) andalso
                    (T#transaction.channel =:= ChannelBin orelse
                     T#transaction.channel =:= Channel),
                case Matches of
                    true  -> Acc + T#transaction.amount;
                    false -> Acc
                end
            end, 0, All),
            case Volume + NewAmount > DailyLimit of
                true  -> {error, daily_limit_exceeded};
                false -> ok
            end
    end.

%% @doc List all configured channel limits.
-dialyzer({nowarn_function, list_all/0}).
-spec list_all() -> [#channel_limit{}].
list_all() ->
    mnesia:dirty_match_object(#channel_limit{_ = '_'}).
