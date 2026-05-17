-module(cb_auth_integration_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2]).
-export([
    health_is_public/1,
    api_requires_authentication/1,
    login_and_me_round_trip/1,
    logout_revokes_session/1,
    admin_can_manage_rbac_resources/1,
    operations_cannot_access_rbac_resources/1,
    observe_mode_falls_back_to_role_checks/1,
    enforce_mode_denies_missing_permissions/1
]).

-define(PORT, 18083).

all() ->
    [
        health_is_public,
        api_requires_authentication,
        login_and_me_round_trip,
        logout_revokes_session,
        admin_can_manage_rbac_resources,
        operations_cannot_access_rbac_resources,
        observe_mode_falls_back_to_role_checks,
        enforce_mode_denies_missing_permissions
    ].

init_per_suite(Config) ->
    inets:start(),
    application:set_env(cb_integration, http_port, ?PORT),
    application:set_env(cb_integration, http_acceptors, 2),
    {ok, _} = application:ensure_all_started(cb_integration),
    Config.

end_per_suite(_Config) ->
    ok = application:stop(cb_integration),
    inets:stop(),
    ok.

init_per_testcase(_TestCase, Config) ->
    application:set_env(cb_integration, rbac_enforced, false),
    lists:foreach(
        fun(Table) -> mnesia:clear_table(Table) end,
        [party, account, transaction, ledger_entry, savings_product,
         loan_products, loan_accounts, loan_repayments, interest_accrual,
            auth_user, auth_session, auth_role, auth_permission,
            auth_role_permission, auth_user_role,
            audit_log, structured_log]
    ),
        ok = cb_rbac:seed_defaults(),
    Config.

health_is_public(_Config) ->
    {ok, {{_, 200, _}, _Headers, Body}} = request(get, "/health", <<>>, []),
    {ok, #{<<"status">> := <<"ok">>}, _} = jsone:try_decode(list_to_binary(Body)),
    ok.

api_requires_authentication(_Config) ->
    {ok, {{_, 401, _}, _Headers, Body}} = request(get, "/api/v1/accounts", <<>>, []),
    {ok, #{<<"error">> := <<"unauthorized">>}, _} = jsone:try_decode(list_to_binary(Body)),
    ok.

login_and_me_round_trip(_Config) ->
    {ok, _UserId} = cb_auth:create_user(<<"admin@example.com">>, <<"secret-pass">>, admin),
    {ok, {{_, 200, _}, _Headers, LoginBody}} = request(
        post,
        "/api/v1/auth/login",
        jsone:encode(#{email => <<"admin@example.com">>, password => <<"secret-pass">>}),
        [{"content-type", "application/json"}]
    ),
    {ok, #{<<"session_id">> := SessionId, <<"user">> := User}, _} =
        jsone:try_decode(list_to_binary(LoginBody)),
    ?assertEqual(<<"admin@example.com">>, maps:get(<<"email">>, User)),
    ?assert(maps:is_key(<<"roles">>, User)),
    ?assert(maps:is_key(<<"permissions">>, User)),

    {ok, {{_, 200, _}, _MeHeaders, MeBody}} = request(
        get,
        "/api/v1/auth/me",
        <<>>,
        auth_headers(SessionId)
    ),
    {ok, #{<<"user">> := MeUser}, _} = jsone:try_decode(list_to_binary(MeBody)),
    ?assertEqual(<<"admin@example.com">>, maps:get(<<"email">>, MeUser)),
    ?assert(maps:is_key(<<"roles">>, MeUser)),
    ?assert(maps:is_key(<<"permissions">>, MeUser)),
    ok.

logout_revokes_session(_Config) ->
    {ok, _UserId} = cb_auth:create_user(<<"ops@example.com">>, <<"logout-pass">>, operations),
    {ok, {{_, 200, _}, _Headers, LoginBody}} = request(
        post,
        "/api/v1/auth/login",
        jsone:encode(#{email => <<"ops@example.com">>, password => <<"logout-pass">>}),
        [{"content-type", "application/json"}]
    ),
    {ok, #{<<"session_id">> := SessionId}, _} = jsone:try_decode(list_to_binary(LoginBody)),

    {ok, {{_, 204, _}, _LogoutHeaders, _LogoutBody}} = request(
        post,
        "/api/v1/auth/logout",
        <<>>,
        auth_headers(SessionId)
    ),

    {ok, {{_, 401, _}, _MeHeaders, MeBody}} = request(
        get,
        "/api/v1/auth/me",
        <<>>,
        auth_headers(SessionId)
    ),
    {ok, #{<<"error">> := <<"unauthorized">>}, _} = jsone:try_decode(list_to_binary(MeBody)),
    ok.

admin_can_manage_rbac_resources(_Config) ->
    {ok, _AdminUserId} = cb_auth:create_user(<<"admin-rbac@example.com">>, <<"secret-pass">>, admin),
    {ok, SessionId} = login(<<"admin-rbac@example.com">>, <<"secret-pass">>),

    {ok, {{_, 200, _}, _PermHeaders, PermBody}} = request(
        get,
        "/api/v1/permissions",
        <<>>,
        auth_headers(SessionId)
    ),
    {ok, PermJson, _} = jsone:try_decode(list_to_binary(PermBody)),
    ?assert(maps:is_key(<<"items">>, PermJson)),

    {ok, {{_, 201, _}, _RoleHeaders, RoleBody}} = request(
        post,
        "/api/v1/roles",
        jsone:encode(#{display_name => <<"Support">>, description => <<"Support role">>}),
        [{"content-type", "application/json"} | auth_headers(SessionId)]
    ),
    {ok, #{<<"role_id">> := RoleId}, _} = jsone:try_decode(list_to_binary(RoleBody)),

    {ok, {{_, 200, _}, _RolePermHeaders, _RolePermBody}} = request(
        put,
        "/api/v1/roles/" ++ binary_to_list(RoleId) ++ "/permissions",
        jsone:encode(#{permission_keys => [<<"user.read">>, <<"permission.read">>]}),
        [{"content-type", "application/json"} | auth_headers(SessionId)]
    ),

    {ok, {{_, 201, _}, _UserHeaders, UserBody}} = request(
        post,
        "/api/v1/users",
        jsone:encode(#{email => <<"rbac-user@example.com">>, password => <<"pw-rbac">>, role => <<"read_only">>}),
        [{"content-type", "application/json"} | auth_headers(SessionId)]
    ),
    {ok, #{<<"user_id">> := UserId}, _} = jsone:try_decode(list_to_binary(UserBody)),

    {ok, {{_, 200, _}, _AssignHeaders, _AssignBody}} = request(
        post,
        "/api/v1/users/" ++ binary_to_list(UserId) ++ "/roles",
        jsone:encode(#{role_id => RoleId}),
        [{"content-type", "application/json"} | auth_headers(SessionId)]
    ),

    {ok, {{_, 200, _}, _DetailHeaders, DetailBody}} = request(
        get,
        "/api/v1/users/" ++ binary_to_list(UserId),
        <<>>,
        auth_headers(SessionId)
    ),
    {ok, UserJson, _} = jsone:try_decode(list_to_binary(DetailBody)),
    ?assert(maps:is_key(<<"roles">>, UserJson)),
    ?assert(maps:is_key(<<"effective">>, UserJson)),
    ok.

operations_cannot_access_rbac_resources(_Config) ->
    {ok, _OpsUserId} = cb_auth:create_user(<<"ops-rbac@example.com">>, <<"secret-pass">>, operations),
    {ok, SessionId} = login(<<"ops-rbac@example.com">>, <<"secret-pass">>),
    {ok, {{_, 403, _}, _Headers, Body}} = request(
        get,
        "/api/v1/users",
        <<>>,
        auth_headers(SessionId)
    ),
    {ok, #{<<"error">> := <<"forbidden">>}, _} = jsone:try_decode(list_to_binary(Body)),
    ok.

observe_mode_falls_back_to_role_checks(_Config) ->
    application:set_env(cb_integration, rbac_enforced, false),
    remove_admin_permission(<<"user.read">>),

    {ok, _AdminUserId} = cb_auth:create_user(<<"observe-admin@example.com">>, <<"secret-pass">>, admin),
    {ok, SessionId} = login(<<"observe-admin@example.com">>, <<"secret-pass">>),

    {ok, {{_, 200, _}, _Headers, Body}} = request(
        get,
        "/api/v1/users",
        <<>>,
        auth_headers(SessionId)
    ),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    ?assert(maps:is_key(<<"items">>, Json)),

    {ok, #{items := LogItems}} = cb_structured_logs:search(#{event => <<"rbac_denied">>, limit => 20}),
    ?assert(lists:any(fun has_observe_user_read_denial/1, LogItems)),
    ok.

enforce_mode_denies_missing_permissions(_Config) ->
    application:set_env(cb_integration, rbac_enforced, true),
    remove_admin_permission(<<"user.read">>),

    {ok, _AdminUserId} = cb_auth:create_user(<<"enforce-admin@example.com">>, <<"secret-pass">>, admin),
    {ok, SessionId} = login(<<"enforce-admin@example.com">>, <<"secret-pass">>),

    {ok, {{_, 403, _}, _Headers, Body}} = request(
        get,
        "/api/v1/users",
        <<>>,
        auth_headers(SessionId)
    ),
    {ok, #{<<"error">> := <<"forbidden">>}, _} = jsone:try_decode(list_to_binary(Body)),

    {ok, #{items := LogItems}} = cb_structured_logs:search(#{event => <<"rbac_denied">>, limit => 20}),
    ?assert(lists:any(fun has_enforce_user_read_denial/1, LogItems)),
    ok.

remove_admin_permission(PermissionKey) ->
    {ok, AdminRole} = cb_rbac:get_role_by_key(<<"admin">>),
    RoleId = maps:get(role_id, AdminRole),
    {ok, ExistingPermissions} = cb_rbac:list_role_permissions(RoleId),
    ok = cb_rbac:set_role_permissions(RoleId, ExistingPermissions -- [PermissionKey]),
    ok.

has_observe_user_read_denial(LogItem) ->
    Metadata = maps:get(metadata, LogItem, #{}),
    maps:get(mode, Metadata, <<>>) =:= <<"observe">> andalso
    maps:get(required_permission, Metadata, <<>>) =:= <<"user.read">> andalso
    maps:get(path, Metadata, <<>>) =:= <<"/api/v1/users">>.

has_enforce_user_read_denial(LogItem) ->
    Metadata = maps:get(metadata, LogItem, #{}),
    maps:get(mode, Metadata, <<>>) =:= <<"enforce">> andalso
    maps:get(required_permission, Metadata, <<>>) =:= <<"user.read">> andalso
    maps:get(path, Metadata, <<>>) =:= <<"/api/v1/users">>.

login(Email, Password) ->
    {ok, {{_, 200, _}, _Headers, LoginBody}} = request(
        post,
        "/api/v1/auth/login",
        jsone:encode(#{email => Email, password => Password}),
        [{"content-type", "application/json"}]
    ),
    {ok, #{<<"session_id">> := SessionId}, _} = jsone:try_decode(list_to_binary(LoginBody)),
    {ok, SessionId}.

request(Method, Path, Body, Headers) ->
    URL = "http://127.0.0.1:" ++ integer_to_list(?PORT) ++ Path,
    case Method of
        get ->
            httpc:request(get, {URL, Headers}, [], []);
        post ->
            httpc:request(post, {URL, Headers, "application/json", binary_to_list(Body)}, [], []);
        put ->
            httpc:request(put, {URL, Headers, "application/json", binary_to_list(Body)}, [], []);
        patch ->
            httpc:request(patch, {URL, Headers, "application/json", binary_to_list(Body)}, [], []);
        delete ->
            httpc:request(delete, {URL, Headers}, [], [])
    end.

auth_headers(SessionId) ->
    [{"authorization", "Bearer " ++ binary_to_list(SessionId)}].
