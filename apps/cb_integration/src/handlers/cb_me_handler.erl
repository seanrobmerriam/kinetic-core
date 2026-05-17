-module(cb_me_handler).

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    case Method of
        <<"GET">> ->
            User = erlang:get(auth_user),
            case User of
                undefined ->
                    error_reply(unauthorized, Req, State);
                _ ->
                    UserId = maps:get(user_id, User, undefined),
                    Effective = case UserId of
                        Id when is_binary(Id) ->
                            case cb_rbac:effective_permissions(Id) of
                                {ok, Payload} -> Payload;
                                {error, _} -> #{roles => [], permissions => []}
                            end;
                        _ ->
                            #{roles => [], permissions => []}
                    end,
                    EnrichedUser = User#{
                        roles => maps:get(roles, Effective, []),
                        permissions => maps:get(permissions, Effective, [])
                    },
                    Resp = #{user => EnrichedUser},
                    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                    Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req),
                    {ok, Req2, State}
            end;
        <<"OPTIONS">> ->
            Req2 = cb_cors:reply_preflight(Req),
            {ok, Req2, State};
        _ ->
            {_Code405, _Hdrs405, _Body405} = cb_http_errors:to_response_with_metrics(method_not_allowed),
            Req2 = cowboy_req:reply(_Code405, _Hdrs405, _Body405, Req),
            {ok, Req2, State}
    end.

error_reply(Reason, Req, State) ->
    {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
    Resp = #{error => ErrorAtom, message => Message},
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
    {ok, Req2, State}.
