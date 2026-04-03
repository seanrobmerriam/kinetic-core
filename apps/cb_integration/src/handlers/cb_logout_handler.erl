-module(cb_logout_handler).

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    case Method of
        <<"POST">> ->
            Session = erlang:get(auth_session),
            case Session of
                undefined ->
                    error_reply(unauthorized, Req, State);
                _ ->
                    ok = cb_auth:delete_session(maps:get(session_id, Session)),
                    Req2 = cowboy_req:reply(204, cb_cors:headers(), <<>>, Req),
                    {ok, Req2, State}
            end;
        <<"OPTIONS">> ->
            Req2 = cb_cors:reply_preflight(Req),
            {ok, Req2, State};
        _ ->
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(405, Headers, <<"{\"error\": \"method_not_allowed\"}">>, Req),
            {ok, Req2, State}
    end.

error_reply(Reason, Req, State) ->
    {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
    Resp = #{error => ErrorAtom, message => Message},
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
    {ok, Req2, State}.
