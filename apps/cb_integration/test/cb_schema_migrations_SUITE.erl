%% @doc Common Test suite for TASK-105 schema migration tooling.
-module(cb_schema_migrations_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, groups/0, init_per_suite/1, end_per_suite/1,
         init_per_testcase/2, end_per_testcase/2]).

-export([
    migrations_endpoint_requires_auth/1,
    rollback_and_reapply_schema_version/1,
    rollback_target_above_current_rejected/1
]).

-define(PORT, 18089).

all() ->
    [{group, schema_migrations}].

groups() ->
    [{schema_migrations, [sequence], [
        migrations_endpoint_requires_auth,
        rollback_and_reapply_schema_version,
        rollback_target_above_current_rejected
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
        [auth_user, auth_session, api_keys, schema_migration_event, schema_version]),
    {ok, _} = cb_schema_migrations:migrate(),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

migrations_endpoint_requires_auth(_Config) ->
    {ok, {{_, 401, _}, _Headers, Body}} = request(get, "/api/v1/operations/schema-migrations", <<>>, []),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    ?assertEqual(<<"unauthorized">>, maps:get(<<"error">>, Json)),
    ok.

rollback_and_reapply_schema_version(_Config) ->
    {ok, SessionId} = create_session(<<"schema-ops@example.com">>, operations),

    {ok, {{_, 200, _}, _RollbackHeaders, RollbackBody}} = request(
        post,
        "/api/v1/operations/schema-migrations/rollback",
        jsone:encode(#{target_version => 0}),
        auth_headers(SessionId) ++ [{"content-type", "application/json"}]
    ),
    {ok, RollbackJson, _} = jsone:try_decode(list_to_binary(RollbackBody)),
    ?assertEqual(0, maps:get(<<"current_version">>, RollbackJson)),

    {ok, {{_, 200, _}, _ApplyHeaders, ApplyBody}} = request(
        post,
        "/api/v1/operations/schema-migrations/apply",
        jsone:encode(#{target_version => 1}),
        auth_headers(SessionId) ++ [{"content-type", "application/json"}]
    ),
    {ok, ApplyJson, _} = jsone:try_decode(list_to_binary(ApplyBody)),
    ?assertEqual(1, maps:get(<<"current_version">>, ApplyJson)),

    {ok, {{_, 200, _}, _ListHeaders, ListBody}} = request(
        get,
        "/api/v1/operations/schema-migrations",
        <<>>,
        auth_headers(SessionId)
    ),
    {ok, ListJson, _} = jsone:try_decode(list_to_binary(ListBody)),
    ?assertEqual(1, maps:get(<<"target_version">>, ListJson)),
    ?assert(length(maps:get(<<"history">>, ListJson)) >= 2),
    ok.

rollback_target_above_current_rejected(_Config) ->
    {ok, SessionId} = create_session(<<"schema-admin@example.com">>, admin),
    {ok, {{_, 409, _}, _Headers, Body}} = request(
        post,
        "/api/v1/operations/schema-migrations/rollback",
        jsone:encode(#{target_version => 2}),
        auth_headers(SessionId) ++ [{"content-type", "application/json"}]
    ),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    ?assertEqual(<<"target_above_current">>, maps:get(<<"error">>, Json)),
    ok.

create_session(Email, Role) ->
    {ok, _} = cb_auth:create_user(Email, <<"pass">>, Role),
    {ok, {{_, 200, _}, _Headers, Body}} = request(
        post,
        "/api/v1/auth/login",
        jsone:encode(#{email => Email, password => <<"pass">>}),
        [{"content-type", "application/json"}]
    ),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    {ok, maps:get(<<"session_id">>, Json)}.

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
            httpc:request(post, {URL, Headers, "application/json", BodyStr}, [{timeout, 5000}], [])
    end.