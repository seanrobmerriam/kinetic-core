-module(cb_roles_handler).

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    RoleId = cowboy_req:binding(role_id, Req, undefined),
    Path = cowboy_req:path(Req),
    handle(Method, RoleId, Path, Req, State).

handle(<<"GET">>, undefined, _Path, Req, State) ->
    case cb_rbac:list_roles() of
        {ok, Roles} -> json_reply(200, #{items => Roles, total => length(Roles)}, Req, State);
        {error, Reason} -> error_reply(Reason, Req, State)
    end;

handle(<<"POST">>, undefined, _Path, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body) of
        {ok, Decoded, _} ->
            DisplayName = maps:get(<<"display_name">>, Decoded, undefined),
            Description = maps:get(<<"description">>, Decoded, <<>>),
            case {DisplayName, Description} of
                {DN, Desc} when is_binary(DN), is_binary(Desc) ->
                    case cb_rbac:create_role(DN, Desc) of
                        {ok, Role} -> json_reply(201, Role, Req2, State);
                        {error, Reason} -> error_reply(Reason, Req2, State)
                    end;
                _ ->
                    error_reply(missing_required_field, Req2, State)
            end;
        _ ->
            error_reply(invalid_json, Req2, State)
    end;

handle(<<"PATCH">>, RoleId, _Path, Req, State) when RoleId =/= undefined ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body) of
        {ok, Decoded, _} when map_size(Decoded) > 0 ->
            case parse_role_updates(Decoded) of
                {ok, Updates} ->
                    case cb_rbac:update_role(RoleId, Updates) of
                        {ok, Role} -> json_reply(200, Role, Req2, State);
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

handle(<<"GET">>, RoleId, Path, Req, State) when RoleId =/= undefined ->
    case ends_with(Path, <<"/permissions">>) of
        true ->
            case cb_rbac:list_role_permissions(RoleId) of
                {ok, PermissionKeys} ->
                    json_reply(200, #{role_id => RoleId, permission_keys => PermissionKeys}, Req, State);
                {error, Reason} ->
                    error_reply(Reason, Req, State)
            end;
        false ->
            method_not_allowed(Req, State)
    end;

handle(<<"PUT">>, RoleId, Path, Req, State) when RoleId =/= undefined ->
    case ends_with(Path, <<"/permissions">>) of
        true ->
            {ok, Body, Req2} = cowboy_req:read_body(Req),
            case jsone:try_decode(Body) of
                {ok, #{<<"permission_keys">> := PermissionKeys}, _} when is_list(PermissionKeys) ->
                    case ensure_binary_list(PermissionKeys) of
                        ok ->
                            case cb_rbac:set_role_permissions(RoleId, PermissionKeys) of
                                ok -> json_reply(200, #{status => <<"updated">>}, Req2, State);
                                {error, Reason} -> error_reply(Reason, Req2, State)
                            end;
                        {error, Reason} ->
                            error_reply(Reason, Req2, State)
                    end;
                _ ->
                    error_reply(missing_required_field, Req2, State)
            end;
        false ->
            method_not_allowed(Req, State)
    end;

handle(<<"OPTIONS">>, _RoleId, _Path, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _RoleId, _Path, Req, State) ->
    method_not_allowed(Req, State).

parse_role_updates(Decoded) ->
    try
        Acc0 = #{},
        Acc1 = case maps:get(<<"display_name">>, Decoded, undefined) of
            undefined -> Acc0;
            DisplayName when is_binary(DisplayName) -> Acc0#{display_name => DisplayName};
            _ -> throw(missing_required_field)
        end,
        Acc2 = case maps:get(<<"description">>, Decoded, undefined) of
            undefined -> Acc1;
            Description when is_binary(Description) -> Acc1#{description => Description};
            _ -> throw(missing_required_field)
        end,
        Acc3 = case maps:get(<<"status">>, Decoded, undefined) of
            undefined -> Acc2;
            <<"active">> -> Acc2#{status => active};
            <<"disabled">> -> Acc2#{status => disabled};
            _ -> throw(invalid_status)
        end,
        case map_size(Acc3) > 0 of
            true -> {ok, Acc3};
            false -> {error, missing_required_field}
        end
    catch
        throw:Reason -> {error, Reason}
    end.

ensure_binary_list([]) ->
    ok;
ensure_binary_list([Bin | Rest]) when is_binary(Bin) ->
    ensure_binary_list(Rest);
ensure_binary_list(_Other) ->
    {error, missing_required_field}.

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
