-module(cb_auth_middleware).
-behaviour(cowboy_middleware).

-export([execute/2]).

-spec execute(cowboy_req:req(), cowboy_middleware:env()) ->
    {ok, cowboy_req:req(), cowboy_middleware:env()} | {stop, cowboy_req:req()}.
execute(Req, Env) ->
    Path = cowboy_req:path(Req),
    case is_public_path(Path) of
        true ->
            {ok, Req, Env};
        false ->
            case authorization_token(Req) of
                undefined ->
                    unauthorized(Req);
                SessionId ->
                    case cb_auth:get_session(SessionId) of
                        {ok, Session} ->
                            erlang:put(auth_session, Session),
                            erlang:put(auth_user, session_user(Session)),
                            Role = maps:get(role, Session),
                            Method = cowboy_req:method(Req),
                            case is_write_method(Method) andalso Role =:= read_only of
                                true  -> forbidden(Req);
                                false -> {ok, Req, Env}
                            end;
                        {error, _Reason} ->
                            unauthorized(Req)
                    end
            end
    end.

is_public_path(<<"/health">>) -> true;
is_public_path(<<"/api/v1/auth/login">>) -> true;
is_public_path(<<"/api/v1/openapi.json">>) -> true;
is_public_path(<<"/metrics">>) -> true;
is_public_path(_) -> false.

is_write_method(<<"POST">>)   -> true;
is_write_method(<<"PUT">>)    -> true;
is_write_method(<<"PATCH">>)  -> true;
is_write_method(<<"DELETE">>) -> true;
is_write_method(_)            -> false.

authorization_token(Req) ->
    case cowboy_req:header(<<"authorization">>, Req) of
        undefined ->
            undefined;
        <<"Bearer ", Token/binary>> ->
            Token;
        _Other ->
            undefined
    end.

session_user(Session) ->
    #{
        user_id => maps:get(user_id, Session),
        email => maps:get(email, Session),
        role => maps:get(role, Session),
        status => maps:get(status, Session)
    }.

unauthorized(Req) ->
    {Status, ErrorAtom, Message} = cb_http_errors:to_response(unauthorized),
    Resp = #{error => ErrorAtom, message => Message},
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    {stop, cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req)}.

forbidden(Req) ->
    {Status, ErrorAtom, Message} = cb_http_errors:to_response(forbidden),
    Resp = #{error => ErrorAtom, message => Message},
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    {stop, cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req)}.
