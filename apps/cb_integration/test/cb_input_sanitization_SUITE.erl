%% @doc Input sanitization and injection prevention test suite (TASK-096).
%%
%% Covers OWASP A03 (Injection) and related input boundary enforcement:
%%
%% - Oversized bodies rejected before handler executes (413)
%% - Wrong Content-Type on write requests rejected (415)
%% - Injection-string currencies rejected gracefully (422, not 500)
%% - Non-integer pagination parameters handled safely (not 500)
%% - Null bytes in query string values rejected (400)
%% - Oversized query string values rejected (400)
-module(cb_input_sanitization_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, groups/0, init_per_suite/1, end_per_suite/1,
         init_per_testcase/2, end_per_testcase/2]).

-export([
    oversized_body_rejected/1,
    wrong_content_type_rejected/1,
    invalid_currency_rejected_gracefully/1,
    invalid_account_currency_rejected_gracefully/1,
    invalid_page_param_safe/1,
    null_byte_in_query_rejected/1,
    oversized_query_value_rejected/1
]).

-define(PORT, 18086).

all() ->
    [{group, input_sanitization}].

groups() ->
    [{input_sanitization, [sequence], [
        oversized_body_rejected,
        wrong_content_type_rejected,
        invalid_currency_rejected_gracefully,
        invalid_account_currency_rejected_gracefully,
        invalid_page_param_safe,
        null_byte_in_query_rejected,
        oversized_query_value_rejected
    ]}].

init_per_suite(Config) ->
    inets:start(),
    application:set_env(cb_integration, http_port, ?PORT),
    application:set_env(cb_integration, http_acceptors, 2),
    {ok, _} = application:ensure_all_started(cb_integration),
    %% Obtain an admin session token for authenticated requests.
    {ok, Token} = create_session(<<"san096-admin@example.com">>, admin),
    [{token, Token} | Config].

end_per_suite(_Config) ->
    ok = application:stop(cb_integration),
    inets:stop(),
    ok.

init_per_testcase(_TestCase, Config) ->
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

%% -------------------------------------------------------------------------
%% Tests
%% -------------------------------------------------------------------------

%% A body whose declared Content-Length exceeds 64 KiB is rejected with 413
%% before the handler reads any data.
oversized_body_rejected(Config) ->
    Token = proplists:get_value(token, Config),
    %% Build a large payload string (70 000 bytes).
    LargeValue = binary:copy(<<"x">>, 70000),
    Body = jsone:encode(#{<<"data">> => LargeValue}),
    {ok, {{_, Code, _}, _Hdrs, RespBody}} =
        request_raw(post, "/api/v1/transactions/deposit", Body,
                    auth_headers(Token) ++ [{"content-type", "application/json"}]),
    ?assertEqual(413, Code),
    {ok, Json, _} = jsone:try_decode(list_to_binary(RespBody)),
    ?assertEqual(<<"request_too_large">>, maps:get(<<"error">>, Json)),
    ok.

%% A POST with Content-Type: text/plain is rejected with 415.
wrong_content_type_rejected(Config) ->
    Token = proplists:get_value(token, Config),
    Body = <<"not json">>,
    {ok, {{_, Code, _}, _Hdrs, RespBody}} =
        request_raw(post, "/api/v1/transactions/deposit", Body,
                    auth_headers(Token) ++ [{"content-type", "text/plain"},
                                            {"content-length", integer_to_list(byte_size(Body))}]),
    ?assertEqual(415, Code),
    {ok, Json, _} = jsone:try_decode(list_to_binary(RespBody)),
    ?assertEqual(<<"unsupported_media_type">>, maps:get(<<"error">>, Json)),
    ok.

%% An injection-style currency string on a deposit returns 422, not 500.
%% Ensures binary_to_existing_atom is never reached for invalid input.
invalid_currency_rejected_gracefully(Config) ->
    Token = proplists:get_value(token, Config),
    Body = jsone:encode(#{
        <<"idempotency_key">> => <<"idem-inject-1">>,
        <<"dest_account_id">> => <<"00000000-0000-0000-0000-000000000001">>,
        <<"amount">>          => 100,
        <<"currency">>        => <<"'; DROP TABLE transactions;--">>,
        <<"description">>     => <<"inject test">>
    }),
    {ok, {{_, Code, _}, _Hdrs, RespBody}} =
        request_raw(post, "/api/v1/transactions/deposit", Body,
                    auth_headers(Token) ++ [{"content-type", "application/json"},
                                            {"content-length", integer_to_list(byte_size(Body))}]),
    ?assert(Code =:= 422 orelse Code =:= 400),
    {ok, Json, _} = jsone:try_decode(list_to_binary(RespBody)),
    ?assertNotEqual(<<"internal_error">>, maps:get(<<"error">>, Json)),
    ok.

%% An atom-exhaustion attempt via currency on account creation returns 422.
invalid_account_currency_rejected_gracefully(Config) ->
    Token = proplists:get_value(token, Config),
    Body = jsone:encode(#{
        <<"party_id">>  => <<"00000000-0000-0000-0000-000000000002">>,
        <<"currency">>  => <<"NOTACURRENCY12345678901234567890">>,
        <<"name">>      => <<"Test Account">>
    }),
    {ok, {{_, Code, _}, _Hdrs, RespBody}} =
        request_raw(post, "/api/v1/accounts", Body,
                    auth_headers(Token) ++ [{"content-type", "application/json"},
                                            {"content-length", integer_to_list(byte_size(Body))}]),
    ?assert(Code =:= 422 orelse Code =:= 400),
    {ok, Json, _} = jsone:try_decode(list_to_binary(RespBody)),
    ?assertNotEqual(<<"internal_error">>, maps:get(<<"error">>, Json)),
    ok.

%% A non-integer ?page value returns a 4xx, not a 500 crash.
invalid_page_param_safe(Config) ->
    Token = proplists:get_value(token, Config),
    {ok, {{_, Code, _}, _Hdrs, _Body}} =
        request(get, "/api/v1/accounts?page=not_a_number", <<>>, auth_headers(Token)),
    ?assert(Code >= 400 andalso Code < 500),
    ok.

%% A query string value containing a null byte is rejected with 400.
null_byte_in_query_rejected(Config) ->
    Token = proplists:get_value(token, Config),
    %% Encode null byte as %00
    {ok, {{_, Code, _}, _Hdrs, RespBody}} =
        request(get, "/api/v1/accounts?page=%001", <<>>, auth_headers(Token)),
    ?assertEqual(400, Code),
    {ok, Json, _} = jsone:try_decode(list_to_binary(RespBody)),
    ?assertEqual(<<"invalid_query_param">>, maps:get(<<"error">>, Json)),
    ok.

%% A query string value exceeding 512 bytes is rejected with 400.
oversized_query_value_rejected(Config) ->
    Token = proplists:get_value(token, Config),
    BigValue = binary_to_list(binary:copy(<<"a">>, 513)),
    Path = "/api/v1/accounts?page=" ++ BigValue,
    {ok, {{_, Code, _}, _Hdrs, RespBody}} =
        request(get, Path, <<>>, auth_headers(Token)),
    ?assertEqual(400, Code),
    {ok, Json, _} = jsone:try_decode(list_to_binary(RespBody)),
    ?assertEqual(<<"invalid_query_param">>, maps:get(<<"error">>, Json)),
    ok.

%% -------------------------------------------------------------------------
%% Helpers
%% -------------------------------------------------------------------------

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
    {ok, maps:get(<<"session_id">>, Json)}.

auth_headers(Token) when is_binary(Token) ->
    [{"authorization", "Bearer " ++ binary_to_list(Token)}].

%% @private Low-level request that passes an explicit body with headers as-is,
%% so we can control Content-Type and Content-Length separately from body.
request_raw(Method, Path, Body, Headers) ->
    URL = "http://localhost:" ++ integer_to_list(?PORT) ++ Path,
    BodyStr = case Body of
        B when is_binary(B) -> binary_to_list(B);
        B                   -> B
    end,
    ContentType = proplists:get_value("content-type", Headers, "application/json"),
    OtherHeaders = proplists:delete("content-type", Headers),
    case Method of
        post ->
            httpc:request(post, {URL, OtherHeaders, ContentType, BodyStr},
                          [{timeout, 5000}], []);
        put ->
            httpc:request(put, {URL, OtherHeaders, ContentType, BodyStr},
                          [{timeout, 5000}], [])
    end.

request(Method, Path, Body, Headers) ->
    URL = "http://localhost:" ++ integer_to_list(?PORT) ++ Path,
    BodyStr = case Body of
        <<>> -> "";
        B when is_binary(B) -> binary_to_list(B);
        B                   -> B
    end,
    case Method of
        get ->
            httpc:request(get, {URL, Headers}, [{timeout, 5000}], []);
        post ->
            httpc:request(post, {URL, Headers, "application/json", BodyStr},
                          [{timeout, 5000}], [])
    end.
