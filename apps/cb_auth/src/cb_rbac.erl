%% @doc RBAC domain service.
%%
%% Provides transactional role, permission, and assignment operations.
-module(cb_rbac).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    seed_defaults/0,
    list_roles/0,
    get_role/1,
    get_role_by_key/1,
    list_permissions/0,
    list_role_permissions/1,
    set_role_permissions/2,
    list_user_roles/1,
    create_role/2,
    update_role/2,
    grant_role_permission/2,
    revoke_role_permission/2,
    assign_user_role/2,
    unassign_user_role/2,
    effective_permissions/1
]).

-type rbac_error() ::
    role_not_found |
    permission_not_found |
    user_not_found |
    role_protected |
    role_key_exists |
    already_assigned |
    not_assigned |
    invalid_role_name |
    database_error.

-spec seed_defaults() -> ok | {error, database_error}.
seed_defaults() ->
    F = fun() ->
        Now = erlang:system_time(millisecond),
        Roles = [
            #{role_key => <<"admin">>, display_name => <<"Admin">>,
              description => <<"Full administrative access">>},
            #{role_key => <<"operations">>, display_name => <<"Operations">>,
              description => <<"Read and write operational access">>},
            #{role_key => <<"read_only">>, display_name => <<"Read Only">>,
              description => <<"Read-only platform access">>}
        ],
        PermissionDefs = [
            #{permission_key => <<"user.read">>, resource => <<"user">>, action => <<"read">>,
              description => <<"Read users">>},
            #{permission_key => <<"user.write">>, resource => <<"user">>, action => <<"write">>,
              description => <<"Create and update users">>},
            #{permission_key => <<"role.read">>, resource => <<"role">>, action => <<"read">>,
              description => <<"Read roles">>},
            #{permission_key => <<"role.write">>, resource => <<"role">>, action => <<"write">>,
              description => <<"Create and update roles">>},
            #{permission_key => <<"permission.read">>, resource => <<"permission">>, action => <<"read">>,
              description => <<"Read permission catalog">>}
        ],
        lists:foreach(fun(RoleDef) -> ensure_system_role(RoleDef, Now) end, Roles),
        lists:foreach(fun(PermissionDef) -> ensure_permission(PermissionDef, Now) end, PermissionDefs),
        ok = ensure_builtin_grants(Now),
        ok
    end,
    case mnesia:transaction(F) of
        {atomic, ok} -> ok;
        {aborted, _Reason} -> {error, database_error}
    end.

-spec list_roles() -> {ok, [map()]} | {error, database_error}.
list_roles() ->
    F = fun() ->
        Match = #auth_role{_ = '_'},
        [role_to_map(Role) || Role <- mnesia:select(auth_role, [{Match, [], ['$_']}])]
    end,
    case mnesia:transaction(F) of
        {atomic, Roles} -> {ok, lists:sort(fun role_sort/2, Roles)};
        {aborted, _Reason} -> {error, database_error}
    end.

-spec get_role(binary()) -> {ok, map()} | {error, role_not_found | database_error}.
get_role(RoleId) when is_binary(RoleId) ->
    F = fun() ->
        case mnesia:read(auth_role, RoleId) of
            [Role] -> {ok, role_to_map(Role)};
            [] -> {error, role_not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

-spec get_role_by_key(binary()) -> {ok, map()} | {error, role_not_found | database_error}.
get_role_by_key(RoleKey) when is_binary(RoleKey) ->
    F = fun() ->
        case mnesia:index_read(auth_role, RoleKey, role_key) of
            [Role] -> {ok, role_to_map(Role)};
            [] -> {error, role_not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

-spec list_permissions() -> {ok, [map()]} | {error, database_error}.
list_permissions() ->
    F = fun() ->
        Match = #auth_permission{_ = '_'},
        [permission_to_map(P) || P <- mnesia:select(auth_permission, [{Match, [], ['$_']}])]
    end,
    case mnesia:transaction(F) of
        {atomic, Permissions} -> {ok, lists:sort(fun permission_sort/2, Permissions)};
        {aborted, _Reason} -> {error, database_error}
    end.

-spec list_role_permissions(binary()) -> {ok, [binary()]} | {error, role_not_found | database_error}.
list_role_permissions(RoleId) when is_binary(RoleId) ->
    F = fun() ->
        case ensure_role_exists(RoleId) of
            ok ->
                Keys = role_permission_keys(RoleId),
                {ok, lists:sort(Keys)};
            {error, _} = Err ->
                Err
        end
    end,
    tx(F).

-spec set_role_permissions(binary(), [binary()]) -> ok | {error, role_not_found | permission_not_found | database_error}.
set_role_permissions(RoleId, PermissionKeys) when is_binary(RoleId), is_list(PermissionKeys) ->
    F = fun() ->
        case ensure_role_exists(RoleId) of
            ok ->
                UniqueKeys = lists:usort(PermissionKeys),
                case validate_permissions_exist(UniqueKeys) of
                    ok ->
                        Now = erlang:system_time(millisecond),
                        Current = role_permission_keys(RoleId),
                        ToGrant = UniqueKeys -- Current,
                        ToRevoke = Current -- UniqueKeys,
                        lists:foreach(fun(Key) -> ok = upsert_role_permission(RoleId, Key, active, Now) end, ToGrant),
                        lists:foreach(fun(Key) -> ok = upsert_role_permission(RoleId, Key, revoked, Now) end, ToRevoke),
                        ok;
                    {error, _} = Err ->
                        Err
                end;
            {error, _} = Err ->
                Err
        end
    end,
    tx(F).

-spec list_user_roles(binary()) -> {ok, [map()]} | {error, user_not_found | database_error}.
list_user_roles(UserId) when is_binary(UserId) ->
    F = fun() ->
        case mnesia:read(auth_user, UserId) of
            [] ->
                {error, user_not_found};
            [_] ->
                Assignments = mnesia:index_read(auth_user_role, UserId, user_id),
                RoleIds = [
                    Assignment#auth_user_role.role_id ||
                    Assignment <- Assignments,
                    Assignment#auth_user_role.status =:= active
                ],
                Roles = [
                    role_to_map(Role) || RoleId <- lists:usort(RoleIds),
                    Role <- read_active_role(RoleId)
                ],
                {ok, lists:sort(fun role_sort/2, Roles)}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

-spec create_role(binary(), binary()) -> {ok, map()} | {error, rbac_error()}.
create_role(DisplayName, Description)
        when is_binary(DisplayName), is_binary(Description) ->
    Trimmed = trim_binary(DisplayName),
    case Trimmed of
        <<>> ->
            {error, invalid_role_name};
        _ ->
            RoleKey = normalize_role_key(Trimmed),
            F = fun() ->
                case mnesia:index_read(auth_role, RoleKey, role_key) of
                    [] ->
                        Now = erlang:system_time(millisecond),
                        Role = #auth_role{
                            role_id = new_uuid(),
                            role_key = RoleKey,
                            display_name = Trimmed,
                            description = Description,
                            status = active,
                            is_system = false,
                            created_at = Now,
                            updated_at = Now
                        },
                        ok = mnesia:write(auth_role, Role, write),
                        {ok, role_to_map(Role)};
                    _ ->
                        {error, role_key_exists}
                end
            end,
            tx(F)
    end.

-spec update_role(binary(), map()) -> {ok, map()} | {error, rbac_error()}.
update_role(RoleId, Updates) when is_binary(RoleId), is_map(Updates) ->
    F = fun() ->
        case mnesia:read(auth_role, RoleId, write) of
            [] ->
                {error, role_not_found};
            [Role] when Role#auth_role.is_system =:= true ->
                {error, role_protected};
            [Role] ->
                Now = erlang:system_time(millisecond),
                Updated = Role#auth_role{
                    display_name = maps:get(display_name, Updates, Role#auth_role.display_name),
                    description = maps:get(description, Updates, Role#auth_role.description),
                    status = maps:get(status, Updates, Role#auth_role.status),
                    updated_at = Now
                },
                ok = mnesia:write(auth_role, Updated, write),
                {ok, role_to_map(Updated)}
        end
    end,
    tx(F).

-spec grant_role_permission(binary(), binary()) -> ok | {error, rbac_error()}.
grant_role_permission(RoleId, PermissionKey)
        when is_binary(RoleId), is_binary(PermissionKey) ->
    F = fun() ->
        case ensure_role_exists(RoleId) of
            ok ->
                case ensure_permission_exists(PermissionKey) of
                    ok ->
                        Now = erlang:system_time(millisecond),
                        upsert_role_permission(RoleId, PermissionKey, active, Now);
                    {error, _} = Err ->
                        Err
                end;
            {error, _} = Err ->
                Err
        end
    end,
    tx(F).

-spec revoke_role_permission(binary(), binary()) -> ok | {error, rbac_error()}.
revoke_role_permission(RoleId, PermissionKey)
        when is_binary(RoleId), is_binary(PermissionKey) ->
    F = fun() ->
        case ensure_role_exists(RoleId) of
            ok ->
                case ensure_permission_exists(PermissionKey) of
                    ok ->
                        Now = erlang:system_time(millisecond),
                        upsert_role_permission(RoleId, PermissionKey, revoked, Now);
                    {error, _} = Err ->
                        Err
                end;
            {error, _} = Err ->
                Err
        end
    end,
    tx(F).

-spec assign_user_role(binary(), binary()) -> ok | {error, rbac_error()}.
assign_user_role(UserId, RoleId) when is_binary(UserId), is_binary(RoleId) ->
    F = fun() ->
        case ensure_user_exists(UserId) of
            ok ->
                case ensure_role_exists(RoleId) of
                    ok ->
                        Now = erlang:system_time(millisecond),
                        upsert_user_role(UserId, RoleId, active, Now);
                    {error, _} = Err ->
                        Err
                end;
            {error, _} = Err ->
                Err
        end
    end,
    tx(F).

-spec unassign_user_role(binary(), binary()) -> ok | {error, rbac_error()}.
unassign_user_role(UserId, RoleId) when is_binary(UserId), is_binary(RoleId) ->
    F = fun() ->
        case ensure_user_exists(UserId) of
            ok ->
                case ensure_role_exists(RoleId) of
                    ok ->
                        Now = erlang:system_time(millisecond),
                        upsert_user_role(UserId, RoleId, revoked, Now);
                    {error, _} = Err ->
                        Err
                end;
            {error, _} = Err ->
                Err
        end
    end,
    tx(F).

-spec effective_permissions(binary()) ->
    {ok, #{roles := [binary()], permissions := [binary()]}} | {error, rbac_error()}.
effective_permissions(UserId) when is_binary(UserId) ->
    F = fun() ->
        case ensure_user_exists(UserId) of
            ok ->
                Assignments = mnesia:index_read(auth_user_role, UserId, user_id),
                ActiveRoleIds = lists:usort([
                    Assignment#auth_user_role.role_id ||
                    Assignment <- Assignments,
                    Assignment#auth_user_role.status =:= active
                ]),
                ActiveRoles = [
                    Role || RoleId <- ActiveRoleIds,
                    Role <- read_active_role(RoleId)
                ],
                RoleKeys = lists:usort([Role#auth_role.role_key || Role <- ActiveRoles]),
                PermissionKeys = lists:usort(lists:flatten([
                    role_permission_keys(Role#auth_role.role_id) || Role <- ActiveRoles
                ])),
                {ok, #{roles => RoleKeys, permissions => PermissionKeys}};
            {error, _} = Err ->
                Err
        end
    end,
    tx(F).

%% ------------------------------------------------------------------
%% Internal helpers
%% ------------------------------------------------------------------

-spec tx(fun(() -> T)) -> T | {error, database_error}.
tx(F) ->
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

ensure_system_role(RoleDef, Now) ->
    RoleKey = maps:get(role_key, RoleDef),
    DisplayName = maps:get(display_name, RoleDef),
    Description = maps:get(description, RoleDef),
    case mnesia:index_read(auth_role, RoleKey, role_key) of
        [] ->
            Role = #auth_role{
                role_id = new_uuid(),
                role_key = RoleKey,
                display_name = DisplayName,
                description = Description,
                status = active,
                is_system = true,
                created_at = Now,
                updated_at = Now
            },
            ok = mnesia:write(auth_role, Role, write),
            ok;
        [Role] when Role#auth_role.is_system =:= false ->
            Updated = Role#auth_role{
                is_system = true,
                updated_at = Now
            },
            ok = mnesia:write(auth_role, Updated, write),
            ok;
        [_Role] ->
            ok
    end.

ensure_permission(PermissionDef, Now) ->
    PermissionKey = maps:get(permission_key, PermissionDef),
    Resource = maps:get(resource, PermissionDef),
    Action = maps:get(action, PermissionDef),
    Description = maps:get(description, PermissionDef),
    case mnesia:index_read(auth_permission, PermissionKey, permission_key) of
        [] ->
            Permission = #auth_permission{
                permission_id = new_uuid(),
                permission_key = PermissionKey,
                resource = Resource,
                action = Action,
                description = Description,
                status = active,
                created_at = Now,
                updated_at = Now
            },
            ok = mnesia:write(auth_permission, Permission, write),
            ok;
        [_Existing] ->
            ok
    end.

ensure_builtin_grants(Now) ->
    Grants = [
        {<<"admin">>, [<<"user.read">>, <<"user.write">>, <<"role.read">>, <<"role.write">>, <<"permission.read">>]},
        {<<"operations">>, [<<"user.read">>, <<"user.write">>, <<"role.read">>, <<"permission.read">>]},
        {<<"read_only">>, [<<"user.read">>, <<"role.read">>, <<"permission.read">>]}
    ],
    lists:foreach(
        fun({RoleKey, PermissionKeys}) ->
            case mnesia:index_read(auth_role, RoleKey, role_key) of
                [Role] ->
                    lists:foreach(
                        fun(PermissionKey) ->
                            ok = upsert_role_permission(Role#auth_role.role_id, PermissionKey, active, Now)
                        end,
                        PermissionKeys
                    );
                [] ->
                    ok
            end
        end,
        Grants
    ),
    ok.

ensure_user_exists(UserId) ->
    case mnesia:read(auth_user, UserId) of
        [] -> {error, user_not_found};
        [_] -> ok
    end.

ensure_role_exists(RoleId) ->
    case read_active_role(RoleId) of
        [] -> {error, role_not_found};
        [_] -> ok
    end.

ensure_permission_exists(PermissionKey) ->
    case mnesia:index_read(auth_permission, PermissionKey, permission_key) of
        [#auth_permission{status = active}] -> ok;
        _ -> {error, permission_not_found}
    end.

validate_permissions_exist([]) ->
    ok;
validate_permissions_exist([PermissionKey | Rest]) ->
    case ensure_permission_exists(PermissionKey) of
        ok -> validate_permissions_exist(Rest);
        {error, _} = Err -> Err
    end.

read_active_role(RoleId) ->
    [
        Role || Role <- mnesia:read(auth_role, RoleId),
        Role#auth_role.status =:= active
    ].

upsert_role_permission(RoleId, PermissionKey, Status, Now) ->
    Existing = [
        Row || Row <- mnesia:index_read(auth_role_permission, RoleId, role_id),
        Row#auth_role_permission.permission_key =:= PermissionKey
    ],
    case Existing of
        [Row] ->
            Updated = Row#auth_role_permission{status = Status, updated_at = Now},
            ok = mnesia:write(auth_role_permission, Updated, write),
            ok;
        [] ->
            Row = #auth_role_permission{
                role_permission_id = new_uuid(),
                role_id = RoleId,
                permission_key = PermissionKey,
                status = Status,
                created_at = Now,
                updated_at = Now
            },
            ok = mnesia:write(auth_role_permission, Row, write),
            ok
    end.

upsert_user_role(UserId, RoleId, Status, Now) ->
    Existing = [
        Row || Row <- mnesia:index_read(auth_user_role, UserId, user_id),
        Row#auth_user_role.role_id =:= RoleId
    ],
    case Existing of
        [Row] ->
            Updated = Row#auth_user_role{status = Status, updated_at = Now},
            ok = mnesia:write(auth_user_role, Updated, write),
            ok;
        [] ->
            Row = #auth_user_role{
                user_role_id = new_uuid(),
                user_id = UserId,
                role_id = RoleId,
                status = Status,
                created_at = Now,
                updated_at = Now
            },
            ok = mnesia:write(auth_user_role, Row, write),
            ok
    end.

role_permission_keys(RoleId) ->
    PermissionRefs = [
        Row#auth_role_permission.permission_key ||
        Row <- mnesia:index_read(auth_role_permission, RoleId, role_id),
        Row#auth_role_permission.status =:= active
    ],
    lists:usort([
        Key || Key <- PermissionRefs,
        is_permission_active(Key)
    ]).

is_permission_active(PermissionKey) ->
    case mnesia:index_read(auth_permission, PermissionKey, permission_key) of
        [#auth_permission{status = active}] -> true;
        _ -> false
    end.

normalize_role_key(DisplayName) ->
    Lower = string:lowercase(binary_to_list(DisplayName)),
    Slug0 = [
        case C of
            _ when C >= $a, C =< $z -> C;
            _ when C >= $0, C =< $9 -> C;
            _ -> $_
        end || C <- Lower
    ],
    Slug1 = collapse_underscores(Slug0),
    list_to_binary(trim_underscores(Slug1)).

collapse_underscores([$_, $_ | Rest]) ->
    collapse_underscores([$_ | Rest]);
collapse_underscores([C | Rest]) ->
    [C | collapse_underscores(Rest)];
collapse_underscores([]) ->
    [].

trim_underscores(Str) ->
    trim_underscores_right(trim_underscores_left(Str)).

trim_underscores_left([$_ | Rest]) ->
    trim_underscores_left(Rest);
trim_underscores_left(Rest) ->
    Rest.

trim_underscores_right(Str) ->
    lists:reverse(trim_underscores_left(lists:reverse(Str))).

trim_binary(Bin) ->
    list_to_binary(string:trim(binary_to_list(Bin))).

new_uuid() ->
    uuid:uuid_to_string(uuid:get_v4(), binary_standard).

role_to_map(Role) ->
    #{
        role_id => Role#auth_role.role_id,
        role_key => Role#auth_role.role_key,
        display_name => Role#auth_role.display_name,
        description => Role#auth_role.description,
        status => Role#auth_role.status,
        is_system => Role#auth_role.is_system,
        created_at => Role#auth_role.created_at,
        updated_at => Role#auth_role.updated_at
    }.

permission_to_map(Permission) ->
    #{
        permission_id => Permission#auth_permission.permission_id,
        permission_key => Permission#auth_permission.permission_key,
        resource => Permission#auth_permission.resource,
        action => Permission#auth_permission.action,
        description => Permission#auth_permission.description,
        status => Permission#auth_permission.status,
        created_at => Permission#auth_permission.created_at,
        updated_at => Permission#auth_permission.updated_at
    }.

role_sort(A, B) ->
    maps:get(role_key, A) =< maps:get(role_key, B).

permission_sort(A, B) ->
    maps:get(permission_key, A) =< maps:get(permission_key, B).
