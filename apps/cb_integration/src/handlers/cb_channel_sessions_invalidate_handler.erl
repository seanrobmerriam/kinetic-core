%% @doc Channel Session Invalidate-All Handler
%%
%% POST /api/v1/parties/:party_id/channel-sessions/invalidate-all
%%
%% Separate handler for the literal path segment, registered before
%% the :session_id wildcard route in Cowboy.
-module(cb_channel_sessions_invalidate_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method  = cowboy_req:method(Req),
    PartyId = cowboy_req:binding(party_id, Req),
    handle(Method, PartyId, Req, State).

handle(<<"POST">>, PartyId, Req, State) ->
    case cb_channel_session:invalidate_all_for_party(PartyId) of
        {ok, Count} ->
            json_reply(200, #{invalidated => Count}, Req, State);
        {error, Reason} ->
            error_reply(Reason, Req, State)
    end;

handle(<<"OPTIONS">>, _PartyId, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _PartyId, Req, State) ->
    {Code, Hdrs, Body} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(Code, Hdrs, Body, Req),
    {ok, Req2, State}.

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
