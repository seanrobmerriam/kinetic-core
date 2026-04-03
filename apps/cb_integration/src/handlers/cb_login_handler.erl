-module(cb_login_handler).

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    case Method of
        <<"POST">> ->
            {ok, Body, Req2} = cowboy_req:read_body(Req),
            case jsone:try_decode(Body) of
                {ok, #{<<"email">> := Email, <<"password">> := Password}, _} ->
                    case cb_auth:authenticate(Email, Password) of
                        {ok, User} ->
                            case cb_auth:create_session(maps:get(user_id, User)) of
                                {ok, Session} ->
                                    Resp = #{
                                        session_id => maps:get(session_id, Session),
                                        expires_at => maps:get(expires_at, Session),
                                        user => user_to_json(User)
                                    },
                                    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                                    Req3 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req2),
                                    {ok, Req3, State};
                                {error, Reason} ->
                                    error_reply(Reason, Req2, State)
                            end;
                        {error, Reason} ->
                            error_reply(Reason, Req2, State)
                    end;
                _ ->
                    error_reply(missing_required_field, Req2, State)
            end;
        <<"OPTIONS">> ->
            Req2 = cb_cors:reply_preflight(Req),
            {ok, Req2, State};
        _ ->
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(405, Headers, <<"{\"error\": \"method_not_allowed\"}">>, Req),
            {ok, Req2, State}
    end.

user_to_json(User) ->
    #{
        user_id => maps:get(user_id, User),
        email => maps:get(email, User),
        role => maps:get(role, User),
        status => maps:get(status, User)
    }.

error_reply(Reason, Req, State) ->
    {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
    Resp = #{error => ErrorAtom, message => Message},
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
    {ok, Req2, State}.
