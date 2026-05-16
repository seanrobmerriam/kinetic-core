%% @doc Common Test suite for TASK-099 SLO/SLA objectives and alert policies.
-module(cb_slo_policies_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, groups/0, init_per_suite/1, end_per_suite/1,
         init_per_testcase/2, end_per_testcase/2]).

-export([
    slo_endpoint_requires_auth/1,
    slo_endpoint_forbids_read_only/1,
    slo_endpoint_returns_objectives/1,
    slo_breach_generates_firing_alert/1
]).

-define(PORT, 18085).

all() ->
    [{group, slo_policies}].

groups() ->
    [{slo_policies, [sequence], [
        slo_endpoint_requires_auth,
        slo_endpoint_forbids_read_only,
        slo_endpoint_returns_objectives,
        slo_breach_generates_firing_alert
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
    ok = cb_metrics_counter:reset(),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

slo_endpoint_requires_auth(_Config) ->
    {ok, {{_, 401, _}, _Headers, Body}} = request(get, "/api/v1/operations/slo", <<>>, []),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    ?assertEqual(<<"unauthorized">>, maps:get(<<"error">>, Json)),
    ok.

slo_endpoint_forbids_read_only(_Config) ->
    {ok, SessionId} = create_session(<<"slo-ro@example.com">>, read_only),
    {ok, {{_, 403, _}, _Headers, Body}} = request(get, "/api/v1/operations/slo", <<>>, auth_headers(SessionId)),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    ?assertEqual(<<"forbidden">>, maps:get(<<"error">>, Json)),
    ok.

slo_endpoint_returns_objectives(_Config) ->
    {ok, SessionId} = create_session(<<"slo-admin@example.com">>, admin),
    {ok, {{_, 200, _}, _Headers, Body}} = request(get, "/api/v1/operations/slo", <<>>, auth_headers(SessionId)),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    ?assert(maps:is_key(<<"generated_at_ms">>, Json)),
    ?assert(maps:is_key(<<"objectives">>, Json)),
    ?assert(maps:is_key(<<"alerts">>, Json)),
    Objectives = maps:get(<<"objectives">>, Json),
    ?assert(length(Objectives) >= 5),
    ok.

slo_breach_generates_firing_alert(_Config) ->
    %% Simulate sustained 5xx failures on transfer path.
    lists:foreach(
      fun(_) ->
          ok = cb_metrics_counter:increment({slo, funds_transfer, total}),
          ok = cb_metrics_counter:increment({slo, funds_transfer, error_5xx})
      end,
      lists:seq(1, 25)
    ),

    {ok, SessionId} = create_session(<<"slo-ops@example.com">>, operations),
    {ok, {{_, 200, _}, _Headers, Body}} = request(get, "/api/v1/operations/slo", <<>>, auth_headers(SessionId)),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),

    Alerts = maps:get(<<"alerts">>, Json),
    FundsAlerts = [A || A <- Alerts, maps:get(<<"objective">>, A) =:= <<"funds_transfer">>],
    ?assert(length(FundsAlerts) >= 1),
    [Alert | _] = FundsAlerts,
    ?assertEqual(<<"firing">>, maps:get(<<"state">>, Alert)),
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
            httpc:request(post, {URL, Headers, "application/json", BodyStr},
                          [{timeout, 5000}], [])
    end.
