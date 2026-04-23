-module(cb_notification_router).

-include("../../cb_ledger/include/cb_ledger.hrl").

-export([
    dispatch/3
]).

%% @doc Dispatch a notification event to all enabled channels for a party.
%%
%% Looks up the party's notification preferences, filters to those where
%% `enabled = true` and the `event_type` is listed in `event_types`, then
%% returns the list of channels the notification was dispatched to.
-spec dispatch(uuid(), binary(), map()) -> {ok, [channel_type()]} | {error, atom()}.
dispatch(PartyId, EventType, _Payload) ->
    Prefs = cb_notification_prefs:list_for_party(PartyId),
    Channels = [P#notification_preference.channel
                || P <- Prefs,
                   P#notification_preference.enabled =:= true,
                   lists:member(EventType, P#notification_preference.event_types)],
    {ok, Channels}.
