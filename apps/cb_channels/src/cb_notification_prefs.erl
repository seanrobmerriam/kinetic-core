%% @doc Notification channel preference management.
%%
%% Controls which channels receive which event-type notifications per party.
%% Each preference record is keyed by {party_id, channel_type} and lists
%% which event types (e.g., "transaction.posted", "payment.failed") should
%% be routed to that channel.
-module(cb_notification_prefs).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    get_pref/2,
    set_pref/4,
    list_for_party/1
]).

%% @doc Get notification preference for a party + channel pair.
%%
%% Returns `not_found` if no explicit preference has been configured.
-spec get_pref(uuid(), channel_type()) ->
    {ok, #notification_preference{}} | {error, not_found}.
get_pref(PartyId, Channel) ->
    Prefs = mnesia:dirty_index_read(notification_preference, PartyId, party_id),
    case [P || P <- Prefs, P#notification_preference.channel =:= Channel] of
        [Pref | _] -> {ok, Pref};
        []         -> {error, not_found}
    end.

%% @doc Set (create or replace) the notification preference for a party + channel.
%%
%% EventTypes is a list of event type binaries, e.g. [<<"transaction.posted">>].
%% An empty list with Enabled=true means all events are routed to this channel.
%% If a preference already exists for the same party + channel, it is updated
%% in place (pref_id is preserved for stable references).
-spec set_pref(uuid(), channel_type(), [binary()], boolean()) ->
    {ok, #notification_preference{}} | {error, atom()}.
set_pref(PartyId, Channel, EventTypes, Enabled)
        when is_list(EventTypes), is_boolean(Enabled) ->
    Now = erlang:system_time(millisecond),
    F = fun() ->
        Existing = mnesia:index_read(notification_preference, PartyId, party_id),
        PrefId = case [P || P <- Existing, P#notification_preference.channel =:= Channel] of
            [P | _] -> P#notification_preference.pref_id;
            []      -> uuid:uuid_to_string(uuid:get_v4(), binary_standard)
        end,
        Pref = #notification_preference{
            pref_id     = PrefId,
            party_id    = PartyId,
            channel     = Channel,
            event_types = EventTypes,
            enabled     = Enabled,
            updated_at  = Now
        },
        ok = mnesia:write(Pref),
        Pref
    end,
    case mnesia:transaction(F) of
        {atomic, Pref}     -> {ok, Pref};
        {aborted, _Reason} -> {error, database_error}
    end;
set_pref(_, _, _, _) ->
    {error, invalid_params}.

%% @doc List all notification preferences for a party.
-spec list_for_party(uuid()) -> [#notification_preference{}].
list_for_party(PartyId) ->
    mnesia:dirty_index_read(notification_preference, PartyId, party_id).
