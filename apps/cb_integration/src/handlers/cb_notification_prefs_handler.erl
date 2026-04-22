%% @doc Notification Channel Preferences Handler
%%
%% Handler for `/api/v1/parties/:party_id/notification-preferences`.
%%
%% Controls which omnichannel delivery targets receive which event-type
%% notifications for a given party.
%%
%% <h2>REST API Endpoints</h2>
%%
%% <ul>
%%   <li><b>GET /api/v1/parties/:party_id/notification-preferences</b> - List preferences</li>
%%   <li><b>PUT /api/v1/parties/:party_id/notification-preferences</b> - Set a preference</li>
%%   <li><b>OPTIONS</b> - CORS preflight</li>
%% </ul>
%%
%% <h2>PUT body</h2>
%%
%% <pre>
%% {
%%   "channel":      "web" | "mobile" | "branch" | "atm",
%%   "event_types":  ["transaction.posted", "payment.failed"],
%%   "enabled":      true
%% }
%% </pre>
%%
%% An empty `event_types` array with `enabled: true` means all events are
%% routed to this channel.
-module(cb_notification_prefs_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method  = cowboy_req:method(Req),
    PartyId = cowboy_req:binding(party_id, Req),
    handle(Method, PartyId, Req, State).

handle(<<"GET">>, PartyId, Req, State) ->
    Prefs = cb_notification_prefs:list_for_party(PartyId),
    json_reply(200, [pref_to_json(P) || P <- Prefs], Req, State);

handle(<<"PUT">>, PartyId, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body) of
        {ok, Decoded, _} ->
            ChannelBin  = maps:get(<<"channel">>,     Decoded, undefined),
            EventTypes  = maps:get(<<"event_types">>, Decoded, []),
            Enabled     = maps:get(<<"enabled">>,     Decoded, true),
            case parse_channel(ChannelBin) of
                {ok, Channel} ->
                    case cb_notification_prefs:set_pref(PartyId, Channel, EventTypes, Enabled) of
                        {ok, Pref} ->
                            json_reply(200, pref_to_json(Pref), Req2, State);
                        {error, Reason} ->
                            error_reply(Reason, Req2, State)
                    end;
                {error, _} ->
                    error_reply(invalid_channel, Req2, State)
            end;
        _ ->
            error_reply(missing_required_field, Req, State)
    end;

handle(<<"OPTIONS">>, _PartyId, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _PartyId, Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(405, Headers, <<"{\"error\":\"method_not_allowed\"}">>, Req),
    {ok, Req2, State}.

%% Internal helpers

pref_to_json(#notification_preference{} = P) ->
    #{
        pref_id     => P#notification_preference.pref_id,
        party_id    => P#notification_preference.party_id,
        channel     => P#notification_preference.channel,
        event_types => P#notification_preference.event_types,
        enabled     => P#notification_preference.enabled,
        updated_at  => P#notification_preference.updated_at
    }.

json_reply(Status, Body, Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Body), Req),
    {ok, Req2, State}.

error_reply(Reason, Req, State) ->
    {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
    Resp = #{error => ErrorAtom, message => Message},
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
    {ok, Req2, State}.

parse_channel(<<"web">>)    -> {ok, web};
parse_channel(<<"mobile">>) -> {ok, mobile};
parse_channel(<<"branch">>) -> {ok, branch};
parse_channel(<<"atm">>)    -> {ok, atm};
parse_channel(_)            -> {error, invalid_channel}.
