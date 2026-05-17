-module(cb_users_handler).

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    UserId = cowboy_req:binding(user_id, Req, undefined),
    RoleId = cowboy_req:binding(role_id, Req, undefined),
    handle(Method, UserId, RoleId, Req, State).

handle(<<"GET">>, undefined, _RoleId, Req, State) ->
    case cb_auth:list_users() of
        {ok, Users} ->
            json_reply(200, #{items => Users, total => length(Users)}, Req, State);
        {error, Reason} ->
            error_reply(Reason, Req, State)
    end;

handle(<<"POST">>, undefined, _RoleId, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body) of
        {ok, Decoded, _} ->
            case parse_create_payload(Decoded) of
                {ok, Email, Password, Role} ->
                    case cb_auth:create_user(Email, Password, Role) of
                        {ok, UserId} ->
                            case assign_builtin_role(UserId, Role) of
                                ok ->
                                    {ok, User} = cb_auth:get_user(UserId),
                                    json_reply(201, User, Req2, State);
                                {error, Reason} ->
                                    error_reply(Reason, Req2, State)
                            end;
                        {error, Reason} ->
                            error_reply(Reason, Req2, State)
                    end;
                {error, Reason} ->
                    error_reply(Reason, Req2, State)
            end;
        _ ->
            error_reply(invalid_json, Req2, State)
    end;

handle(<<"GET">>, UserId, undefined, Req, State) when UserId =/= undefined ->
    case cb_validate:safe_path_param(UserId) of
        {ok, SafeUserId} ->
            case cb_auth:get_user(SafeUserId) of
                {ok, User} ->
                    {ok, Roles} = cb_rbac:list_user_roles(SafeUserId),
                    {ok, Effective} = cb_rbac:effective_permissions(SafeUserId),
                    json_reply(200, User#{roles => Roles, effective => Effective}, Req, State);
                {error, Reason} ->
                    error_reply(Reason, Req, State)
            end;
        {error, _} ->
            error_reply(invalid_path_param, Req, State)
    end;

handle(<<"PATCH">>, UserId, undefined, Req, State) when UserId =/= undefined ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case cb_validate:safe_path_param(UserId) of
        {ok, SafeUserId} ->
            case jsone:try_decode(Body) of
                {ok, Decoded, _} when map_size(Decoded) > 0 ->
                    case parse_update_payload(Decoded) of
                        {ok, Updates} ->
                            case cb_auth:update_user(SafeUserId, Updates) of
                                {ok, User} -> json_reply(200, User, Req2, State);
                                {error, Reason} -> error_reply(Reason, Req2, State)
                            end;
                        {error, Reason} ->
                            error_reply(Reason, Req2, State)
                    end;
                {ok, _Decoded, _} ->
                    error_reply(missing_required_field, Req2, State);
                _ ->
                    error_reply(invalid_json, Req2, State)
            end;
        {error, _} ->
            error_reply(invalid_path_param, Req2, State)
    end;

handle(<<"POST">>, UserId, undefined, Req, State) when UserId =/= undefined ->
    Path = cowboy_req:path(Req),
    case ends_with(Path, <<"/roles">>) of
        true ->
            {ok, Body, Req2} = cowboy_req:read_body(Req),
            case {cb_validate:safe_path_param(UserId), jsone:try_decode(Body)} of
                {{ok, SafeUserId}, {ok, Decoded, _}} ->
                    case maps:get(<<"role_id">>, Decoded, undefined) of
                        RoleId when is_binary(RoleId) ->
                            case cb_rbac:assign_user_role(SafeUserId, RoleId) of
                                ok -> json_reply(200, #{status => <<"assigned">>}, Req2, State);
                                {error, Reason} -> error_reply(Reason, Req2, State)
                            end;
                        _ ->
                            error_reply(missing_required_field, Req2, State)
                    end;
                {{error, _}, _} -> error_reply(invalid_path_param, Req2, State);
                {_, _} -> error_reply(invalid_json, Req2, State)
            end;
        false ->
            method_not_allowed(Req, State)
    end;

handle(<<"DELETE">>, UserId, RoleId, Req, State)
        when UserId =/= undefined, RoleId =/= undefined ->
    case {cb_validate:safe_path_param(UserId), cb_validate:safe_path_param(RoleId)} of
        {{ok, SafeUserId}, {ok, SafeRoleId}} ->
            case cb_rbac:unassign_user_role(SafeUserId, SafeRoleId) of
                ok -> json_reply(200, #{status => <<"unassigned">>}, Req, State);
                {error, Reason} -> error_reply(Reason, Req, State)
            end;
        _ ->
            error_reply(invalid_path_param, Req, State)
    end;

handle(<<"OPTIONS">>, _UserId, _RoleId, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _UserId, _RoleId, Req, State) ->
    method_not_allowed(Req, State).

assign_builtin_role(UserId, Role) ->
    RoleKey = role_atom_to_key(Role),
    case cb_rbac:get_role_by_key(RoleKey) of
        {ok, RoleMap} ->
            cb_rbac:assign_user_role(UserId, maps:get(role_id, RoleMap));
        {error, Reason} ->
            {error, Reason}
    end.

parse_create_payload(Decoded) ->
    Email = maps:get(<<"email">>, Decoded, undefined),
    Password = maps:get(<<"password">>, Decoded, undefined),
    RoleBin = maps:get(<<"role">>, Decoded, undefined),
    case {Email, Password, RoleBin} of
        {E, P, R} when is_binary(E), is_binary(P), is_binary(R) ->
            case {cb_validate:safe_text(E, 320), cb_validate:safe_text(P, 256), parse_role(R)} of
                {{ok, SafeE}, {ok, SafeP}, {ok, Role}} -> {ok, SafeE, SafeP, Role};
                {{error, Reason}, _, _} -> {error, Reason};
                {_, {error, Reason}, _} -> {error, Reason};
                {_, _, {error, Reason}} -> {error, Reason}
            end;
        _ ->
            {error, missing_required_field}
    end.

parse_update_payload(Decoded) ->
    try
        Acc0 = #{},
        Acc1 = maybe_put_email(Acc0, maps:get(<<"email">>, Decoded, undefined)),
        Acc2 = maybe_put_role(Acc1, maps:get(<<"role">>, Decoded, undefined)),
        Acc3 = maybe_put_status(Acc2, maps:get(<<"status">>, Decoded, undefined)),
        case map_size(Acc3) > 0 of
            true -> {ok, Acc3};
            false -> {error, missing_required_field}
        end
    catch
        throw:Reason -> {error, Reason}
    end.

maybe_put_email(Acc, undefined) ->
    Acc;
maybe_put_email(Acc, Email) when is_binary(Email) ->
    case cb_validate:safe_text(Email, 320) of
        {ok, Safe} -> Acc#{email => Safe};
        {error, Reason} -> throw(Reason)
    end;
maybe_put_email(_Acc, _Other) ->
    throw(missing_required_field).

maybe_put_role(Acc, undefined) ->
    Acc;
maybe_put_role(Acc, RoleBin) when is_binary(RoleBin) ->
    case parse_role(RoleBin) of
        {ok, Role} -> Acc#{role => Role};
        {error, Reason} -> throw(Reason)
    end;
maybe_put_role(_Acc, _Other) ->
    throw(missing_required_field).

maybe_put_status(Acc, undefined) ->
    Acc;
maybe_put_status(Acc, <<"active">>) ->
    Acc#{status => active};
maybe_put_status(Acc, <<"disabled">>) ->
    Acc#{status => disabled};
maybe_put_status(_Acc, _Other) ->
    throw(invalid_status).

parse_role(<<"admin">>) -> {ok, admin};
parse_role(<<"operations">>) -> {ok, operations};
parse_role(<<"read_only">>) -> {ok, read_only};
parse_role(_) -> {error, missing_required_field}.

role_atom_to_key(admin) -> <<"admin">>;
role_atom_to_key(operations) -> <<"operations">>;
role_atom_to_key(read_only) -> <<"read_only">>.

ends_with(Path, Suffix) when is_binary(Path), is_binary(Suffix) ->
    PathSize = byte_size(Path),
    SuffixSize = byte_size(Suffix),
    case PathSize >= SuffixSize of
        true -> binary:part(Path, PathSize - SuffixSize, SuffixSize) =:= Suffix;
        false -> false
    end.

method_not_allowed(Req, State) ->
    {_Code405, _Hdrs405, _Body405} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(_Code405, _Hdrs405, _Body405, Req),
    {ok, Req2, State}.

error_reply(Reason, Req, State) ->
    {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
    Resp = #{error => ErrorAtom, message => Message},
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
    {ok, Req2, State}.

json_reply(Status, Body, Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Body), Req),
    {ok, Req2, State}.
