%% @doc Common Test suite for TASK-106: backward compatibility policy enforcement.
-module(cb_schema_compat_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, groups/0, init_per_suite/1, end_per_suite/1,
         init_per_testcase/2, end_per_testcase/2]).

-export([
    compat_check_passes_on_clean_schema/1,
    compat_endpoint_requires_auth/1,
    compat_endpoint_returns_ok_on_clean_schema/1,
    apply_blocked_on_compat_violation/1
]).

-define(PORT, 18090).

all() ->
    [{group, compat}].

groups() ->
    [{compat, [sequence], [
        compat_check_passes_on_clean_schema,
        compat_endpoint_requires_auth,
        compat_endpoint_returns_ok_on_clean_schema,
        apply_blocked_on_compat_violation
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

%% Direct module test — no HTTP stack needed.
compat_check_passes_on_clean_schema(_Config) ->
    ?assertEqual(ok, cb_schema_compat:check()),
    ok.

compat_endpoint_requires_auth(_Config) ->
    {ok, {{_, 401, _}, _, Body}} =
        request(get, "/api/v1/operations/schema-migrations/compat", <<>>, []),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    ?assertEqual(<<"unauthorized">>, maps:get(<<"error">>, Json)),
    ok.

compat_endpoint_returns_ok_on_clean_schema(_Config) ->
    {ok, SessionId} = create_session(<<"compat-ops@example.com">>, operations),
    {ok, {{_, 200, _}, _, Body}} =
        request(get, "/api/v1/operations/schema-migrations/compat", <<>>, auth_headers(SessionId)),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    ?assertEqual(<<"ok">>, maps:get(<<"status">>, Json)),
    ?assertEqual([], maps:get(<<"violations">>, Json)),
    ok.

%% Verify that a detected compat violation blocks migration apply.
apply_blocked_on_compat_violation(_Config) ->
    %% Roll back to version 0 so there is a pending migration to apply.
    {ok, _} = cb_schema_migrations:rollback_to(0),

    %% Now corrupt the schema by removing a column from the party table in-memory.
    %% We do this by deleting and recreating the table with a missing field.
    mnesia:delete_table(party),
    {atomic, ok} = mnesia:create_table(party, [
        {ram_copies, [node()]},
        {attributes, [party_id, full_name, email, status]},  %% intentionally stripped
        {index, [email, status]}
    ]),

    Result = cb_schema_migrations:migrate(),
    ?assertMatch({error, {backward_compat_violations, _}}, Result),

    %% Restore the table for subsequent test teardown.
    mnesia:delete_table(party),
    ok = cb_schema:create_tables(),
    ok.

create_session(Email, Role) ->
    {ok, _} = cb_auth:create_user(Email, <<"pass">>, Role),
    {ok, {{_, 200, _}, _, Body}} = request(
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
        <<>>             -> "";
        B when is_binary(B) -> binary_to_list(B);
        B                -> B
    end,
    case Method of
        get  -> httpc:request(get, {URL, Headers}, [{timeout, 5000}], []);
        post -> httpc:request(post, {URL, Headers, "application/json", BodyStr}, [{timeout, 5000}], [])
    end.
