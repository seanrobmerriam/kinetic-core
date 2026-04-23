%% @doc Channel Sessions Handler
%%
%% Endpoints:
%%   GET    /api/v1/parties/:party_id/channel-sessions
%%   POST   /api/v1/parties/:party_id/channel-sessions
%%   POST   /api/v1/parties/:party_id/channel-sessions/invalidate-all
%%   GET    /api/v1/parties/:party_id/channel-sessions/:session_id
%%   DELETE /api/v1/parties/:party_id/channel-sessions/:session_id
-module(cb_channel_sessions_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method    = cowboy_req:method(Req),
    PartyId   = cowboy_req:binding(party_id, Req),
    SessionId = cowboy_req:binding(session_id, Req),
    handle(Method, PartyId, SessionId, Req, State).

%% List sessions for party
handle(<<"GET">>, PartyId, undefined, Req, State) ->
    {ok, Sessions} = cb_channel_session:list_for_party(PartyId),
    json_reply(200, [session_to_json(S) || S <- Sessions], Req, State);

%% Create a new session
handle(<<"POST">>, PartyId, undefined, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body) of
        {ok, Decoded, _} ->
            ChannelBin = maps:get(<<"channel">>, Decoded, undefined),
            case parse_channel(ChannelBin) of
                {ok, Channel} ->
                    case cb_channel_session:create(PartyId, Channel) of
                        {ok, Session} -> json_reply(201, session_to_json(Session), Req2, State);
                        {error, R}    -> error_reply(R, Req2, State)
                    end;
                {error, _} ->
                    error_reply(invalid_channel, Req2, State)
            end;
        _ ->
            error_reply(missing_required_field, Req, State)
    end;

%% Get a specific session
handle(<<"GET">>, _PartyId, SessionId, Req, State) ->
    case cb_channel_session:get(SessionId) of
        {ok, Session}      -> json_reply(200, session_to_json(Session), Req, State);
        {error, not_found} -> error_reply(not_found, Req, State)
    end;

%% Invalidate a specific session
handle(<<"DELETE">>, _PartyId, SessionId, Req, State) ->
    case cb_channel_session:invalidate(SessionId) of
        {ok, Session}      -> json_reply(200, session_to_json(Session), Req, State);
        {error, not_found} -> error_reply(not_found, Req, State);
        {error, R}         -> error_reply(R, Req, State)
    end;

handle(<<"OPTIONS">>, _PartyId, _Session, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _PartyId, _Session, Req, State) ->
    {Code, Hdrs, Body} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(Code, Hdrs, Body, Req),
    {ok, Req2, State}.

session_to_json(#channel_session{} = S) ->
    #{
        session_id     => S#channel_session.session_id,
        party_id       => S#channel_session.party_id,
        channel        => S#channel_session.channel,
        status         => S#channel_session.status,
        initiated_at   => S#channel_session.initiated_at,
        invalidated_at => S#channel_session.invalidated_at
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
