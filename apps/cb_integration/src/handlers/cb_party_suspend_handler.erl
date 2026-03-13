-module(cb_party_suspend_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    PartyId = cowboy_req:binding(party_id, Req),
    handle(Method, PartyId, Req, State).

handle(<<"POST">>, PartyId, Req, State) ->
    case cb_party:suspend_party(PartyId) of
        {ok, Party} ->
            Resp = party_to_json(Party),
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State};
        {error, Reason} ->
            {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
            Resp = #{error => ErrorAtom, message => Message},
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State}
    end;

handle(<<"OPTIONS">>, _PartyId, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _PartyId, Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(405, Headers, <<"{\"error\": \"method_not_allowed\"}">>, Req),
    {ok, Req2, State}.

party_to_json(Party) ->
    #{
        party_id => Party#party.party_id,
        full_name => Party#party.full_name,
        email => Party#party.email,
        status => Party#party.status,
        created_at => Party#party.created_at,
        updated_at => Party#party.updated_at
    }.
