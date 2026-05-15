%% @doc TASK-095 regulatory evidence + signed export regression suite.
-module(cb_regulatory_evidence_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, groups/0, init_per_suite/1, end_per_suite/1,
         init_per_testcase/2, end_per_testcase/2]).

-export([
    admin_can_generate_signed_evidence_export/1,
    generated_export_is_retrievable/1,
    verify_endpoint_reports_verified_true/1,
    operations_cannot_generate_evidence_export/1,
    admin_can_list_generated_exports/1
]).

-define(PORT, 18086).

all() ->
    [{group, regulatory_evidence}].

groups() ->
    [{regulatory_evidence, [sequence], [
        admin_can_generate_signed_evidence_export,
        generated_export_is_retrievable,
        verify_endpoint_reports_verified_true,
        operations_cannot_generate_evidence_export,
        admin_can_list_generated_exports
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
        [auth_user, auth_session, report_export]),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

admin_can_generate_signed_evidence_export(_Config) ->
    {ok, AdminSession} = create_session(<<"evidence-admin1@example.com">>, admin),
    {ok, {{_, 201, _}, _Headers, Body}} = request(
        post,
        "/api/v1/audit/evidence/accounts",
        jsone:encode(#{}),
        auth_headers(AdminSession) ++ [{"content-type", "application/json"}]
    ),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    ?assert(maps:is_key(<<"export_id">>, Json)),
    Params = maps:get(<<"parameters">>, Json),
    ?assert(maps:is_key(<<"signature">>, Params)),
    ?assert(maps:is_key(<<"payload_hash">>, Params)),
    ?assertEqual(<<"hmac-sha256">>, maps:get(<<"signature_alg">>, Params)),
    ok.

generated_export_is_retrievable(_Config) ->
    {ok, AdminSession} = create_session(<<"evidence-admin2@example.com">>, admin),
    {ok, {{_, 201, _}, _, Body}} = request(
        post,
        "/api/v1/audit/evidence/accounts",
        jsone:encode(#{}),
        auth_headers(AdminSession) ++ [{"content-type", "application/json"}]
    ),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    ExportId = maps:get(<<"export_id">>, Json),

    {ok, {{_, 200, _}, _, GetBody}} = request(
        get,
        "/api/v1/audit/evidence/exports/" ++ binary_to_list(ExportId),
        <<>>,
        auth_headers(AdminSession)
    ),
    {ok, GetJson, _} = jsone:try_decode(list_to_binary(GetBody)),
    ?assertEqual(ExportId, maps:get(<<"export_id">>, GetJson)),
    Params = maps:get(<<"parameters">>, GetJson),
    ?assert(maps:is_key(<<"signature">>, Params)),
    ok.

verify_endpoint_reports_verified_true(_Config) ->
    {ok, AdminSession} = create_session(<<"evidence-admin3@example.com">>, admin),
    {ok, {{_, 201, _}, _, Body}} = request(
        post,
        "/api/v1/audit/evidence/accounts",
        jsone:encode(#{}),
        auth_headers(AdminSession) ++ [{"content-type", "application/json"}]
    ),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    ExportId = maps:get(<<"export_id">>, Json),

    {ok, {{_, 200, _}, _, VerifyBody}} = request(
        post,
        "/api/v1/audit/evidence/exports/" ++ binary_to_list(ExportId) ++ "/verify",
        <<>>,
        auth_headers(AdminSession)
    ),
    {ok, VerifyJson, _} = jsone:try_decode(list_to_binary(VerifyBody)),
    ?assertEqual(true, maps:get(<<"verified">>, VerifyJson)),
    ok.

operations_cannot_generate_evidence_export(_Config) ->
    {ok, OpsSession} = create_session(<<"evidence-ops@example.com">>, operations),
    {ok, {{_, 403, _}, _, Body}} = request(
        post,
        "/api/v1/audit/evidence/accounts",
        jsone:encode(#{}),
        auth_headers(OpsSession) ++ [{"content-type", "application/json"}]
    ),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    ?assertEqual(<<"forbidden">>, maps:get(<<"error">>, Json)),
    ok.

admin_can_list_generated_exports(_Config) ->
    {ok, AdminSession} = create_session(<<"evidence-admin4@example.com">>, admin),
    {ok, {{_, 201, _}, _, _}} = request(
        post,
        "/api/v1/audit/evidence/accounts",
        jsone:encode(#{}),
        auth_headers(AdminSession) ++ [{"content-type", "application/json"}]
    ),
    {ok, {{_, 200, _}, _, Body}} = request(
        get,
        "/api/v1/audit/evidence/exports",
        <<>>,
        auth_headers(AdminSession)
    ),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    Total = maps:get(<<"total">>, Json),
    ?assert(Total >= 1),
    ok.

%% Helpers

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
    SessionId = maps:get(<<"session_id">>, Json),
    {ok, SessionId}.

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
