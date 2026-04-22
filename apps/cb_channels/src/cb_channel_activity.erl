%% @doc Channel activity logging.
%%
%% Records inbound API request events tagged with channel and party context.
%% Used for audit, analytics, and omnichannel journey tracking.
-module(cb_channel_activity).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    log/4,
    log/5,
    list_for_party/1,
    list_for_channel/1,
    list_recent/1
]).

%% @doc Log an activity entry.
%%
%% Channel and PartyId may be `undefined` for unauthenticated requests.
-spec log(channel_type() | undefined, uuid() | undefined, binary(), binary()) ->
    ok | {error, database_error}.
log(Channel, PartyId, Action, Endpoint) ->
    log(Channel, PartyId, Action, Endpoint, 0).

-spec log(channel_type() | undefined, uuid() | undefined, binary(), binary(), non_neg_integer()) ->
    ok | {error, database_error}.
log(Channel, PartyId, Action, Endpoint, StatusCode) ->
    Now = erlang:system_time(millisecond),
    LogId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
    Entry = #channel_activity{
        log_id      = LogId,
        channel     = Channel,
        party_id    = PartyId,
        action      = Action,
        endpoint    = Endpoint,
        status_code = StatusCode,
        created_at  = Now
    },
    F = fun() -> mnesia:write(Entry) end,
    case mnesia:transaction(F) of
        {atomic, ok}       -> ok;
        {aborted, _Reason} -> {error, database_error}
    end.

%% @doc Retrieve all activity entries for a specific party.
-spec list_for_party(uuid()) -> [#channel_activity{}].
list_for_party(PartyId) ->
    mnesia:dirty_index_read(channel_activity, PartyId, party_id).

%% @doc Retrieve all activity entries for a specific channel type.
-spec list_for_channel(channel_type()) -> [#channel_activity{}].
list_for_channel(Channel) ->
    mnesia:dirty_index_read(channel_activity, Channel, channel).

%% @doc Retrieve the N most recent activity entries (descending by time).
-dialyzer({nowarn_function, list_recent/1}).
-spec list_recent(pos_integer()) -> [#channel_activity{}].
list_recent(Limit) when is_integer(Limit), Limit > 0 ->
    All = mnesia:dirty_match_object(#channel_activity{_ = '_'}),
    Sorted = lists:sort(fun(A, B) -> A#channel_activity.created_at >= B#channel_activity.created_at end, All),
    lists:sublist(Sorted, Limit).
