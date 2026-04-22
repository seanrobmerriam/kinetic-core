-module(cb_auth_integration_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2]).
-export([
    health_is_public/1,
    api_requires_authentication/1,
    login_and_me_round_trip/1,
    logout_revokes_session/1
]).

-define(PORT, 18083).

all() ->
    [
        health_is_public,
        api_requires_authentication,
        login_and_me_round_trip,
        logout_revokes_session
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
    lists:foreach(
        fun(Table) -> mnesia:clear_table(Table) end,
        [party, account, transaction, ledger_entry, savings_product,
         loan_products, loan_accounts, loan_repayments, interest_accrual,
         auth_user, auth_session, audit_log]
    ),
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

    {ok, {{_, 200, _}, _MeHeaders, MeBody}} = request(
        get,
        "/api/v1/auth/me",
        <<>>,
        auth_headers(SessionId)
    ),
    {ok, #{<<"user">> := MeUser}, _} = jsone:try_decode(list_to_binary(MeBody)),
    ?assertEqual(<<"admin@example.com">>, maps:get(<<"email">>, MeUser)),
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

request(Method, Path, Body, Headers) ->
    URL = "http://127.0.0.1:" ++ integer_to_list(?PORT) ++ Path,
    case Method of
        get ->
            httpc:request(get, {URL, Headers}, [], []);
        post ->
            httpc:request(post, {URL, Headers, "application/json", binary_to_list(Body)}, [], [])
    end.

auth_headers(SessionId) ->
    [{"authorization", "Bearer " ++ binary_to_list(SessionId)}].
