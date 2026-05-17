-module(cb_rbac_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2]).
-export([
    seed_defaults_creates_catalog/1,
    assign_role_yields_effective_permissions/1,
    system_role_update_is_protected/1
]).

all() ->
    [
        seed_defaults_creates_catalog,
        assign_role_yields_effective_permissions,
        system_role_update_is_protected
    ].

init_per_suite(Config) ->
    mnesia:start(),
    cb_schema:create_tables(),
    {ok, _} = application:ensure_all_started(cb_auth),
    Config.

end_per_suite(_Config) ->
    ok = application:stop(cb_auth),
    mnesia:stop(),
    mnesia:delete_schema([node()]),
    ok.

init_per_testcase(_TestCase, Config) ->
    lists:foreach(
        fun(Table) -> mnesia:clear_table(Table) end,
        [auth_user, auth_session, auth_role, auth_permission,
         auth_role_permission, auth_user_role, audit_log]
    ),
    ok = cb_rbac:seed_defaults(),
    Config.

seed_defaults_creates_catalog(_Config) ->
    {ok, Roles} = cb_rbac:list_roles(),
    {ok, Permissions} = cb_rbac:list_permissions(),
    ?assert(length(Roles) >= 3),
    ?assert(length(Permissions) >= 5),
    ?assert(lists:any(fun(Role) -> maps:get(role_key, Role) =:= <<"admin">> end, Roles)),
    ?assert(lists:any(fun(P) -> maps:get(permission_key, P) =:= <<"user.read">> end, Permissions)),
    ok.

assign_role_yields_effective_permissions(_Config) ->
    {ok, UserId} = cb_auth:create_user(<<"rbac-user@example.com">>, <<"secret-pass">>, read_only),
    {ok, Roles} = cb_rbac:list_roles(),
    AdminRole = find_role(<<"admin">>, Roles),
    ok = cb_rbac:assign_user_role(UserId, maps:get(role_id, AdminRole)),
    {ok, Effective} = cb_rbac:effective_permissions(UserId),
    RoleKeys = maps:get(roles, Effective),
    PermissionKeys = maps:get(permissions, Effective),
    ?assert(lists:member(<<"admin">>, RoleKeys)),
    ?assert(lists:member(<<"role.write">>, PermissionKeys)),
    ok.

system_role_update_is_protected(_Config) ->
    {ok, Roles} = cb_rbac:list_roles(),
    ReadOnlyRole = find_role(<<"read_only">>, Roles),
    ?assertEqual(
        {error, role_protected},
        cb_rbac:update_role(maps:get(role_id, ReadOnlyRole), #{description => <<"new description">>})
    ),
    ok.

find_role(RoleKey, Roles) ->
    hd([Role || Role <- Roles, maps:get(role_key, Role) =:= RoleKey]).
