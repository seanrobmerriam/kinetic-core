-module(cb_login_handler).

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    case Method of
        <<"POST">> ->
            {ok, Body, Req2} = cowboy_req:read_body(Req),
            case jsone:try_decode(Body) of
                {ok, #{<<"email">> := Email, <<"password">> := Password} = Decoded, _} ->
                    ChannelType = parse_channel_type(maps:get(<<"channel">>, Decoded, undefined)),
                    case cb_auth:authenticate(Email, Password) of
                        {ok, User} ->
                            case cb_auth:create_session(maps:get(user_id, User), ChannelType) of
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
            {_Code405, _Hdrs405, _Body405} = cb_http_errors:to_response_with_metrics(method_not_allowed),
            Req2 = cowboy_req:reply(_Code405, _Hdrs405, _Body405, Req),
            {ok, Req2, State}
    end.

user_to_json(User) ->
    #{
        user_id => maps:get(user_id, User),
        email => maps:get(email, User),
        role => maps:get(role, User),
        status => maps:get(status, User)
    }.

parse_channel_type(<<"web">>)    -> web;
parse_channel_type(<<"mobile">>) -> mobile;
parse_channel_type(<<"branch">>) -> branch;
parse_channel_type(<<"atm">>)    -> atm;
parse_channel_type(_)            -> undefined.

error_reply(Reason, Req, State) ->
    {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
    Resp = #{error => ErrorAtom, message => Message},
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
    {ok, Req2, State}.
