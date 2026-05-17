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
                Token ->
                    case try_session(Token) of
                        {ok, Session} ->
                            erlang:put(auth_session, Session),
                            erlang:put(auth_user, session_user(Session)),
                            Role = maps:get(role, Session),
                            Permissions = session_permissions(Session),
                            erlang:put(auth_permissions, Permissions),
                            authorize(Role, Permissions, Req, Env);
                        {error, _} ->
                            case cb_api_keys:authenticate_key(Token) of
                                {ok, KeyMeta} ->
                                    erlang:put(auth_session, KeyMeta),
                                    erlang:put(auth_user, key_user(KeyMeta)),
                                    erlang:put(api_key_rate_limit, maps:get(rate_limit_per_min, KeyMeta)),
                                    erlang:put(api_key_id, maps:get(key_id, KeyMeta)),
                                    cb_api_usage:record_request(
                                        maps:get(key_id, KeyMeta),
                                        cowboy_req:method(Req),
                                        cowboy_req:path(Req)
                                    ),
                                    Role = maps:get(role, KeyMeta),
                                    Permissions = role_permissions(Role),
                                    erlang:put(auth_permissions, Permissions),
                                    authorize(Role, Permissions, Req, Env);
                                {error, _} ->
                                    case cb_oauth:validate_token(Token) of
                                        {ok, OAuthCtx} ->
                                            erlang:put(auth_session, OAuthCtx),
                                            erlang:put(auth_user, oauth_user(OAuthCtx)),
                                            Role = maps:get(role, OAuthCtx),
                                            Permissions = role_permissions(Role),
                                            erlang:put(auth_permissions, Permissions),
                                            authorize(Role, Permissions, Req, Env);
                                        {error, _} ->
                                            unauthorized(Req)
                                    end
                            end
                    end
            end
    end.

is_public_path(<<"/health">>) -> true;
is_public_path(<<"/api/v1/auth/login">>) -> true;
is_public_path(<<"/api/v1/oauth/token">>) -> true;
is_public_path(<<"/api/v1/openapi.json">>) -> true;
is_public_path(<<"/metrics">>) -> true;
is_public_path(_) -> false.

is_write_method(<<"POST">>)   -> true;
is_write_method(<<"PUT">>)    -> true;
is_write_method(<<"PATCH">>)  -> true;
is_write_method(<<"DELETE">>) -> true;
is_write_method(_)            -> false.

authorize(Role, Permissions, Req, Env) ->
    Method = cowboy_req:method(Req),
    Path = cowboy_req:path(Req),
    case required_permission(Method, Path) of
        undefined ->
            authorize_role(Role, Req, Env);
        PermissionKey ->
            case lists:member(PermissionKey, Permissions) of
                true ->
                    {ok, Req, Env};
                false ->
                    maybe_observe_or_forbid(Role, PermissionKey, Method, Path, Req, Env)
            end
    end.

authorize_role(Role, Req, Env) ->
    Method = cowboy_req:method(Req),
    Path = cowboy_req:path(Req),
    case role_allows(Role, Method, Path) of
        true -> {ok, Req, Env};
        false -> forbidden(Req)
    end.

maybe_observe_or_forbid(Role, PermissionKey, Method, Path, Req, Env) ->
    case rbac_enforced() of
        true ->
            forbidden(Req);
        false ->
            observe_denial(Role, PermissionKey, Method, Path),
            authorize_role(Role, Req, Env)
    end.

rbac_enforced() ->
    case application:get_env(cb_integration, rbac_enforced, false) of
        true -> true;
        _ -> false
    end.

required_permission(_Method, Path) when Path =:= <<"/api/v1/permissions">> ->
    <<"permission.read">>;
required_permission(_Method, Path) when Path =:= <<"/api/v1/users">> ->
    case _Method of
        <<"GET">> -> <<"user.read">>;
        _ -> <<"user.write">>
    end;
required_permission(_Method, Path) when Path =:= <<"/api/v1/roles">> ->
    case _Method of
        <<"GET">> -> <<"role.read">>;
        _ -> <<"role.write">>
    end;
required_permission(Method, Path) ->
    case has_prefix(Path, <<"/api/v1/users/">>) of
        true ->
            case Method of
                <<"GET">> -> <<"user.read">>;
                _ -> <<"user.write">>
            end;
        false ->
            case has_prefix(Path, <<"/api/v1/roles/">>) of
                true ->
                    case Method of
                        <<"GET">> -> <<"role.read">>;
                        _ -> <<"role.write">>
                    end;
                false ->
                    undefined
            end
    end.

observe_denial(Role, PermissionKey, Method, Path) ->
    logger:warning(
        "rbac_observe_denial role=~p required_permission=~p method=~p path=~p",
        [Role, PermissionKey, Method, Path]
    ).

session_permissions(Session) ->
    UserId = maps:get(user_id, Session, undefined),
    case UserId of
        undefined -> [];
        _ ->
            case cb_rbac:effective_permissions(UserId) of
                {ok, Effective} -> maps:get(permissions, Effective, []);
                {error, _} -> []
            end
    end.

role_permissions(Role) ->
    RoleKey = role_key(Role),
    case RoleKey of
        undefined -> [];
        _ ->
            case cb_rbac:get_role_by_key(RoleKey) of
                {ok, RoleMap} ->
                    RoleId = maps:get(role_id, RoleMap),
                    case cb_rbac:list_role_permissions(RoleId) of
                        {ok, PermissionKeys} -> PermissionKeys;
                        {error, _} -> []
                    end;
                {error, _} -> []
            end
    end.

role_key(admin) -> <<"admin">>;
role_key(operations) -> <<"operations">>;
role_key(read_only) -> <<"read_only">>;
role_key(_) -> undefined.

role_allows(Role, Method, Path) ->
    case required_role(Method, Path) of
        admin_only ->
            role_rank(Role) >= role_rank(admin);
        write ->
            role_rank(Role) >= role_rank(operations);
        read ->
            role_rank(Role) >= role_rank(read_only)
    end.

required_role(Method, Path) ->
    case is_admin_only_boundary(Method, Path) of
        true -> admin_only;
        false ->
            case is_operations_boundary(Path) of
                true -> write;
                false ->
                    case is_write_method(Method) of
                        true -> write;
                        false -> read
                    end
            end
    end.

is_operations_boundary(Path) ->
    has_prefix(Path, <<"/api/v1/operations/">>).

is_admin_only_boundary(_Method, <<"/api/v1/api-keys">>) -> true;
is_admin_only_boundary(_Method, <<"/api/v1/users">>) -> true;
is_admin_only_boundary(_Method, <<"/api/v1/roles">>) -> true;
is_admin_only_boundary(_Method, <<"/api/v1/permissions">>) -> true;
is_admin_only_boundary(<<"GET">>, <<"/api/v1/channel-limits">>) -> true;
is_admin_only_boundary(_Method, <<"/api/v1/audit/retention-policies">>) -> true;
is_admin_only_boundary(_Method, <<"/api/v1/audit/apply-retention">>) -> true;
is_admin_only_boundary(_Method, <<"/api/v1/audit/evidence/exports">>) -> true;
is_admin_only_boundary(Method, Path) ->
    case has_prefix(Path, <<"/api/v1/users/">>) orelse
         has_prefix(Path, <<"/api/v1/roles/">>) orelse
         has_prefix(Path, <<"/api/v1/permissions/">>) orelse
         has_prefix(Path, <<"/api/v1/api-keys/">>) of
        true -> true;
        false ->
            case has_prefix(Path, <<"/api/v1/channel-limits/">>) orelse
                 has_prefix(Path, <<"/api/v1/channel-features/">>) of
                true ->
                    Method =:= <<"PUT">> orelse Method =:= <<"PATCH">> orelse Method =:= <<"DELETE">>;
                false ->
                    has_prefix(Path, <<"/api/v1/audit/evidence/">>) orelse
                    has_prefix(Path, <<"/api/v1/cluster/">>) orelse
                    has_prefix(Path, <<"/api/v1/scaling/">>) orelse
                    has_prefix(Path, <<"/api/v1/recovery/">>)
            end
    end.

role_rank(admin) -> 3;
role_rank(operations) -> 2;
role_rank(read_only) -> 1;
role_rank(_) -> 0.

has_prefix(Bin, Prefix) when is_binary(Bin), is_binary(Prefix) ->
    PrefixSize = byte_size(Prefix),
    BinSize = byte_size(Bin),
    case BinSize >= PrefixSize of
        true -> binary:part(Bin, 0, PrefixSize) =:= Prefix;
        false -> false
    end.

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

try_session(Token) ->
    case cb_auth:get_session(Token) of
        {ok, Session} -> {ok, Session};
        {error, _}    -> {error, unauthorized}
    end.

key_user(KeyMeta) ->
    #{
        user_id => maps:get(key_id, KeyMeta),
        email   => maps:get(partner_id, KeyMeta),
        role    => maps:get(role, KeyMeta),
        status  => active
    }.

oauth_user(OAuthCtx) ->
    #{
        user_id => maps:get(client_id, OAuthCtx),
        email   => maps:get(client_id, OAuthCtx),
        role    => maps:get(role, OAuthCtx),
        status  => active
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
