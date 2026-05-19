%% @doc Common Test suite for TASK-104 incident response automation.
-module(cb_incident_response_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, groups/0, init_per_suite/1, end_per_suite/1,
         init_per_testcase/2, end_per_testcase/2]).

-export([
    incidents_endpoint_requires_auth/1,
    incidents_sync_creates_active_incident/1,
    templates_endpoint_returns_postmortem_templates/1,
    resolve_incident_generates_postmortem_draft/1
]).

-define(PORT, 18088).

all() ->
    [{group, incidents}].

groups() ->
    [{incidents, [sequence], [
        incidents_endpoint_requires_auth,
        incidents_sync_creates_active_incident,
        templates_endpoint_returns_postmortem_templates,
        resolve_incident_generates_postmortem_draft
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
        [auth_user, auth_session, api_keys, incident_response]),
    ok = cb_metrics_counter:reset(),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

incidents_endpoint_requires_auth(_Config) ->
    {ok, {{_, 401, _}, _Headers, Body}} = request(get, "/api/v1/operations/incidents", <<>>, []),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    ?assertEqual(<<"unauthorized">>, maps:get(<<"error">>, Json)),
    ok.

incidents_sync_creates_active_incident(_Config) ->
    %% Force a sustained breach for funds transfer objective.
    lists:foreach(
      fun(_) ->
          ok = cb_metrics_counter:increment({slo, funds_transfer, total}),
          ok = cb_metrics_counter:increment({slo, funds_transfer, error_5xx})
      end,
      lists:seq(1, 25)
    ),

    {ok, SessionId} = create_session(<<"incident-ops@example.com">>, operations),

    {ok, {{_, 200, _}, _Headers, SyncBody}} = request(
        post,
        "/api/v1/operations/incidents/sync",
        <<>>,
        auth_headers(SessionId)
    ),
    {ok, SyncJson, _} = jsone:try_decode(list_to_binary(SyncBody)),
    ?assert(maps:get(<<"active_alerts">>, SyncJson) >= 1),

    {ok, {{_, 200, _}, _ListHeaders, Body}} = request(
        get,
        "/api/v1/operations/incidents",
        <<>>,
        auth_headers(SessionId)
    ),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    ?assert(maps:get(<<"total">>, Json) >= 1),
    [Incident | _] = maps:get(<<"items">>, Json),
    ?assertEqual(<<"open">>, maps:get(<<"status">>, Incident)),
    ?assert(maps:is_key(<<"escalation_tier">>, Incident)),
    ok.

templates_endpoint_returns_postmortem_templates(_Config) ->
    {ok, SessionId} = create_session(<<"incident-admin@example.com">>, admin),
    {ok, {{_, 200, _}, _Headers, Body}} = request(
        get,
        "/api/v1/operations/incidents/templates",
        <<>>,
        auth_headers(SessionId)
    ),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    Items = maps:get(<<"items">>, Json),
    ?assert(length(Items) >= 3),
    ok.

resolve_incident_generates_postmortem_draft(_Config) ->
    %% Trigger an incident first.
    lists:foreach(
      fun(_) ->
          ok = cb_metrics_counter:increment({slo, auth_login, total}),
          ok = cb_metrics_counter:increment({slo, auth_login, error_5xx})
      end,
      lists:seq(1, 25)
    ),
    {ok, SessionId} = create_session(<<"incident-resolve-ops@example.com">>, operations),

    {ok, {{_, 200, _}, _, _}} = request(
        post,
        "/api/v1/operations/incidents/sync",
        <<>>,
        auth_headers(SessionId)
    ),

    {ok, {{_, 200, _}, _Headers, ListBody}} = request(
        get,
        "/api/v1/operations/incidents",
        <<>>,
        auth_headers(SessionId)
    ),
    {ok, ListJson, _} = jsone:try_decode(list_to_binary(ListBody)),
    [Incident | _] = maps:get(<<"items">>, ListJson),
    IncidentId = maps:get(<<"incident_id">>, Incident),

    ResolvePath = "/api/v1/operations/incidents/" ++ binary_to_list(IncidentId) ++ "/resolve",
    {ok, {{_, 200, _}, _ResolveHeaders, ResolveBody}} = request(
        post,
        ResolvePath,
        jsone:encode(#{summary => <<"Issue mitigated via rollout rollback">>}),
        auth_headers(SessionId) ++ [{"content-type", "application/json"}]
    ),
    {ok, ResolveJson, _} = jsone:try_decode(list_to_binary(ResolveBody)),
    ?assertEqual(<<"resolved">>, maps:get(<<"status">>, ResolveJson)),
    Draft = maps:get(<<"postmortem_draft">>, ResolveJson),
    ?assert(maps:is_key(<<"template_id">>, Draft)),
    ?assert(maps:is_key(<<"sections">>, Draft)),
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
