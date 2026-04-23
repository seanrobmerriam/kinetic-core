-module(cb_channel_features).

-include("../../cb_ledger/include/cb_ledger.hrl").

-export([
    set_flag/3,
    get_flag/2,
    is_enabled/2,
    list_for_channel/1
]).

-spec set_flag(channel_type(), binary(), boolean()) ->
    {ok, #channel_feature_flag{}} | {error, atom()}.
set_flag(Channel, Feature, Enabled) ->
    Now = erlang:system_time(millisecond),
    Flag = #channel_feature_flag{
        flag_key   = {Channel, Feature},
        channel    = Channel,
        feature    = Feature,
        enabled    = Enabled,
        updated_at = Now
    },
    case mnesia:transaction(fun() -> mnesia:write(Flag) end) of
        {atomic, ok}      -> {ok, Flag};
        {aborted, Reason} -> {error, Reason}
    end.

-spec get_flag(channel_type(), binary()) ->
    {ok, #channel_feature_flag{}} | {error, not_found}.
get_flag(Channel, Feature) ->
    case mnesia:dirty_read(channel_feature_flag, {Channel, Feature}) of
        [Flag] -> {ok, Flag};
        []     -> {error, not_found}
    end.

-spec is_enabled(channel_type(), binary()) -> boolean().
is_enabled(Channel, Feature) ->
    case get_flag(Channel, Feature) of
        {ok, #channel_feature_flag{enabled = true}}  -> true;
        _                                             -> false
    end.

-spec list_for_channel(channel_type()) -> {ok, [#channel_feature_flag{}]}.
list_for_channel(Channel) ->
    Flags = mnesia:dirty_index_read(channel_feature_flag, Channel, channel),
    {ok, Flags}.
