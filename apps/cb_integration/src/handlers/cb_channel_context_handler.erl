%% @doc Channel Context Handler
%%
%% GET /api/v1/parties/:party_id/channel-context/:channel
-module(cb_channel_context_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method    = cowboy_req:method(Req),
    PartyId   = cowboy_req:binding(party_id, Req),
    ChannelB  = cowboy_req:binding(channel, Req),
    handle(Method, PartyId, ChannelB, Req, State).

handle(<<"GET">>, PartyId, ChannelBin, Req, State) ->
    case parse_channel(ChannelBin) of
        {ok, Channel} ->
            case cb_channel_context:get_context(PartyId, Channel) of
                {ok, Context} ->
                    json_reply(200, Context, Req, State);
                {error, not_found} ->
                    error_reply(not_found, Req, State)
            end;
        {error, _} ->
            error_reply(invalid_channel, Req, State)
    end;

handle(<<"OPTIONS">>, _PartyId, _Channel, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _PartyId, _Channel, Req, State) ->
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

parse_channel(<<"web">>)    -> {ok, web};
parse_channel(<<"mobile">>) -> {ok, mobile};
parse_channel(<<"branch">>) -> {ok, branch};
parse_channel(<<"atm">>)    -> {ok, atm};
parse_channel(_)            -> {error, invalid_channel}.
