%% @doc TASK-100 structured log aggregation regression suite.
-module(cb_structured_logs_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).

-export([
    search_returns_logged_request_entries/1,
    export_returns_csv_for_matching_logs/1,
    retention_policy_deletes_old_logs/1
]).

-define(PORT, 18087).

all() ->
    [
        search_returns_logged_request_entries,
        export_returns_csv_for_matching_logs,
        retention_policy_deletes_old_logs
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
    lists:foreach(fun(T) -> mnesia:clear_table(T) end,
        [auth_user, auth_session, structured_log, audit_retention_policy]),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

search_returns_logged_request_entries(_Config) ->
    CorrelationId = <<"trace-search-001">>,
    {ok, {{_, 200, _}, _, _}} = httpc:request(
        get,
        {url("/health"), [{"x-correlation-id", binary_to_list(CorrelationId)}]},
        [{timeout, 5000}],
        []
    ),
    {ok, SessionId} = create_session(<<"logs-search-admin@example.com">>, admin),

    {ok, {{_, 200, _}, _, Body}} = request(
        get,
        "/api/v1/operations/logs?correlation_id=" ++ binary_to_list(CorrelationId),
        <<>>,
        auth_headers(SessionId)
    ),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    Items = maps:get(<<"items">>, Json),
    ?assert(length(Items) >= 2),
    ?assert(lists:all(fun(Item) -> maps:get(<<"correlation_id">>, Item) =:= CorrelationId end, Items)),
    ok.

export_returns_csv_for_matching_logs(_Config) ->
    CorrelationId = <<"trace-export-001">>,
    ok = cb_structured_logs:write(info, #{
        event => request_received,
        correlation_id => CorrelationId,
        method => <<"GET">>,
        path => <<"/health">>,
        metadata => #{source => test}
    }),
    {ok, SessionId} = create_session(<<"logs-export-admin@example.com">>, admin),

    {ok, {{_, 200, _}, Headers, Body}} = request(
        get,
        "/api/v1/operations/logs/export?correlation_id=" ++ binary_to_list(CorrelationId),
        <<>>,
        auth_headers(SessionId)
    ),
    ?assertEqual("text/csv", header_value("content-type", Headers)),
    ?assertNotEqual(nomatch, binary:match(list_to_binary(Body), CorrelationId)),
    ok.

retention_policy_deletes_old_logs(_Config) ->
    OldCreatedAt = erlang:system_time(millisecond) - 3 * 86400000,
    _ = mnesia:dirty_write(#structured_log{
        log_id = <<"old-log-1">>,
        level = <<"info">>,
        event = <<"request_received">>,
        correlation_id = <<"trace-old-001">>,
        method = <<"GET">>,
        path = <<"/health">>,
        status_code = undefined,
        duration = undefined,
        metadata = #{seed => true},
        created_at = OldCreatedAt
    }),
    {ok, SessionId} = create_session(<<"logs-retention-admin@example.com">>, admin),

    {ok, {{_, 200, _}, _, _}} = request(
        post,
        "/api/v1/operations/logs/retention",
        jsone:encode(#{retention_days => 1}),
        auth_headers(SessionId) ++ [{"content-type", "application/json"}]
    ),
    {ok, {{_, 200, _}, _, ApplyBody}} = request(
        post,
        "/api/v1/operations/logs/retention/apply",
        <<>>,
        auth_headers(SessionId)
    ),
    {ok, ApplyJson, _} = jsone:try_decode(list_to_binary(ApplyBody)),
    ?assertEqual(1, maps:get(<<"deleted">>, ApplyJson)),

    {ok, {{_, 200, _}, _, SearchBody}} = request(
        get,
        "/api/v1/operations/logs?correlation_id=trace-old-001",
        <<>>,
        auth_headers(SessionId)
    ),
    {ok, SearchJson, _} = jsone:try_decode(list_to_binary(SearchBody)),
    ?assertEqual(0, maps:get(<<"total">>, SearchJson)),
    ok.

create_session(Email, Role) ->
    {ok, _} = cb_auth:create_user(Email, <<"pass">>, Role),
    login(Email, <<"pass">>).

login(Email, Password) ->
    {ok, {{_, 200, _}, _Headers, Body}} = request(
        post,
        "/api/v1/auth/login",
        jsone:encode(#{email => Email, password => Password}),
        [{"content-type", "application/json"}]
    ),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    {ok, maps:get(<<"session_id">>, Json)}.

auth_headers(Token) when is_binary(Token) ->
    [{"authorization", "Bearer " ++ binary_to_list(Token)}].

request(Method, Path, Body, Headers) ->
    URL = url(Path),
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

url(Path) ->
    "http://localhost:" ++ integer_to_list(?PORT) ++ Path.

header_value(Name, Headers) ->
    case lists:keyfind(Name, 1, Headers) of
        {_, Value} -> Value;
        false -> undefined
    end.