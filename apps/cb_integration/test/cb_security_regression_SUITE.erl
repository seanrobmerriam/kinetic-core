%% @doc Security regression suite scaffold for TASK-097.
%%
%% Initial focus:
%% - Broken access control (A01)
%% - Authentication failures (A07)
-module(cb_security_regression_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, groups/0, init_per_suite/1, end_per_suite/1,
         init_per_testcase/2, end_per_testcase/2]).

-export([
    unauthenticated_protected_endpoint_denied/1,
    operations_forbidden_admin_boundary/1,
    read_only_forbidden_admin_boundary/1,
    admin_allowed_admin_boundary/1
]).

-define(PORT, 18084).

all() ->
    [{group, security_regression}].

groups() ->
    [{security_regression, [sequence], [
        unauthenticated_protected_endpoint_denied,
        operations_forbidden_admin_boundary,
        read_only_forbidden_admin_boundary,
        admin_allowed_admin_boundary
    ]}].

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
    lists:foreach(fun(T) -> mnesia:clear_table(T) end,
        [auth_user, auth_session, api_keys]),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

unauthenticated_protected_endpoint_denied(_Config) ->
    {ok, {{_, 401, _}, _Headers, Body}} = request(get, "/api/v1/accounts", <<>>, []),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    ?assertEqual(<<"unauthorized">>, maps:get(<<"error">>, Json)),
    ok.

operations_forbidden_admin_boundary(_Config) ->
    {ok, AdminSession} = create_session(<<"sec-admin@example.com">>, admin),
    {ok, OpsKey} = create_api_key(AdminSession, <<"operations">>),
    {ok, {{_, 403, _}, _Headers, Body}} = request(get, "/api/v1/api-keys", <<>>, auth_headers(OpsKey)),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    ?assertEqual(<<"forbidden">>, maps:get(<<"error">>, Json)),
    ok.

read_only_forbidden_admin_boundary(_Config) ->
    {ok, AdminSession} = create_session(<<"sec-admin2@example.com">>, admin),
    {ok, RoKey} = create_api_key(AdminSession, <<"read_only">>),
    {ok, {{_, 403, _}, _Headers, Body}} = request(get, "/api/v1/api-keys", <<>>, auth_headers(RoKey)),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    ?assertEqual(<<"forbidden">>, maps:get(<<"error">>, Json)),
    ok.

admin_allowed_admin_boundary(_Config) ->
    {ok, AdminSession} = create_session(<<"sec-admin3@example.com">>, admin),
    {ok, AdminKey} = create_api_key(AdminSession, <<"admin">>),
    {ok, {{_, 200, _}, _Headers, Body}} = request(get, "/api/v1/api-keys", <<>>, auth_headers(AdminKey)),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    ?assert(maps:is_key(<<"items">>, Json)),
    ok.

%% Helpers

create_session(Email, Role) ->
    {ok, _} = cb_auth:create_user(Email, <<"pass">>, Role),
    login(Email, <<"pass">>).

login(Email, Password) ->
    {ok, {{_, 200, _}, _Headers, Body}} = request(
        post, "/api/v1/auth/login",
        jsone:encode(#{email => Email, password => Password}),
        [{"content-type", "application/json"}]
    ),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    SessionId = maps:get(<<"session_id">>, Json),
    {ok, SessionId}.

create_api_key(SessionId, RoleBin) ->
    {ok, {{_, 201, _}, _Headers, Body}} = request(
        post,
        "/api/v1/api-keys",
        jsone:encode(#{
            <<"label">> => <<"security-key">>,
            <<"partner_id">> => <<"security-partner">>,
            <<"role">> => RoleBin,
            <<"rate_limit_per_min">> => 300
        }),
        auth_headers(SessionId) ++ [{"content-type", "application/json"}]
    ),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    {ok, maps:get(<<"key_secret">>, Json)}.

auth_headers(Token) when is_binary(Token) ->
    [{"authorization", "Bearer " ++ binary_to_list(Token)}].

request(Method, Path, Body, Headers) ->
    URL = "http://localhost:" ++ integer_to_list(?PORT) ++ Path,
    BodyStr = case Body of
        <<>> -> "";
        B when is_binary(B) -> binary_to_list(B);
        B -> B
    end,
    case Method of
        get ->
            httpc:request(get, {URL, Headers}, [{timeout, 5000}], []);
        post ->
            httpc:request(post, {URL, Headers, "application/json", BodyStr},
                          [{timeout, 5000}], [])
    end.
