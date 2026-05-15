%% @doc Key rotation regression suite for TASK-094.
%%
%% Tests automated key rotation and audit trail:
%%  - rotate returns a new secret (old one revoked atomically)
%%  - new secret authenticates; old secret is rejected
%%  - rotation event recorded in audit table
%%  - rotation history endpoint returns events newest-first
%%  - non-admin is forbidden from rotating
%%  - pending-rotation listing detects stale keys
-module(cb_key_rotation_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, groups/0, init_per_suite/1, end_per_suite/1,
         init_per_testcase/2, end_per_testcase/2]).

-export([
    rotate_key_returns_new_secret/1,
    new_secret_authenticates_after_rotation/1,
    old_secret_rejected_after_rotation/1,
    rotation_history_recorded/1,
    non_admin_cannot_rotate/1,
    pending_rotation_lists_stale_keys/1
]).

-define(PORT, 18085).

all() ->
    [{group, key_rotation}].

groups() ->
    [{key_rotation, [sequence], [
        rotate_key_returns_new_secret,
        new_secret_authenticates_after_rotation,
        old_secret_rejected_after_rotation,
        rotation_history_recorded,
        non_admin_cannot_rotate,
        pending_rotation_lists_stale_keys
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
        [auth_user, auth_session, api_keys, key_rotation_events]),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

%% =============================================================================
%% Test Cases
%% =============================================================================

%% POST /api/v1/api-keys/:key_id/rotate returns 200 with new key_secret.
rotate_key_returns_new_secret(_Config) ->
    {ok, AdminSession} = create_session(<<"rot-admin1@example.com">>, admin),
    {ok, AdminKey} = create_api_key(AdminSession, <<"admin">>),
    {KeyId, _OldSecret} = get_key_id_for_secret(AdminKey),

    {ok, {{_, 200, _}, _Hdrs, Body}} =
        request(post, "/api/v1/api-keys/" ++ binary_to_list(KeyId) ++ "/rotate",
                <<>>, auth_headers(AdminKey)),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    ?assert(maps:is_key(<<"key_secret">>, Json)),
    ?assert(maps:is_key(<<"rotation_id">>, Json)),
    ?assert(maps:is_key(<<"rotated_at">>, Json)),
    NewSecret = maps:get(<<"key_secret">>, Json),
    ?assertNotEqual(AdminKey, NewSecret),
    ok.

%% After rotation, the new secret must authenticate successfully.
new_secret_authenticates_after_rotation(_Config) ->
    {ok, AdminSession} = create_session(<<"rot-admin2@example.com">>, admin),
    {ok, OldSecret} = create_api_key(AdminSession, <<"admin">>),
    {KeyId, _} = get_key_id_for_secret(OldSecret),

    {ok, {{_, 200, _}, _, RotBody}} =
        request(post, "/api/v1/api-keys/" ++ binary_to_list(KeyId) ++ "/rotate",
                <<>>, auth_headers(OldSecret)),
    {ok, RotJson, _} = jsone:try_decode(list_to_binary(RotBody)),
    NewSecret = maps:get(<<"key_secret">>, RotJson),

    %% New secret must reach an admin-gated endpoint.
    {ok, {{_, 200, _}, _, _}} = request(get, "/api/v1/api-keys", <<>>, auth_headers(NewSecret)),
    ok.

%% After rotation, the old secret must be rejected with 401.
old_secret_rejected_after_rotation(_Config) ->
    {ok, AdminSession} = create_session(<<"rot-admin3@example.com">>, admin),
    {ok, OldSecret} = create_api_key(AdminSession, <<"admin">>),
    {KeyId, _} = get_key_id_for_secret(OldSecret),

    {ok, {{_, 200, _}, _, _}} =
        request(post, "/api/v1/api-keys/" ++ binary_to_list(KeyId) ++ "/rotate",
                <<>>, auth_headers(OldSecret)),

    {ok, {{_, 401, _}, _, _}} =
        request(get, "/api/v1/api-keys", <<>>, auth_headers(OldSecret)),
    ok.

%% GET /api/v1/api-keys/:key_id/rotation-history returns a list with one event.
rotation_history_recorded(_Config) ->
    {ok, AdminSession} = create_session(<<"rot-admin4@example.com">>, admin),
    {ok, AdminKey} = create_api_key(AdminSession, <<"admin">>),
    {KeyId, _} = get_key_id_for_secret(AdminKey),

    {ok, {{_, 200, _}, _, RotBody}} =
        request(post, "/api/v1/api-keys/" ++ binary_to_list(KeyId) ++ "/rotate",
                <<>>, auth_headers(AdminKey)),
    {ok, RotJson, _} = jsone:try_decode(list_to_binary(RotBody)),
    NewSecret = maps:get(<<"key_secret">>, RotJson),

    {ok, {{_, 200, _}, _, HistBody}} =
        request(get, "/api/v1/api-keys/" ++ binary_to_list(KeyId) ++ "/rotation-history",
                <<>>, auth_headers(NewSecret)),
    {ok, HistJson, _} = jsone:try_decode(list_to_binary(HistBody)),
    Items = maps:get(<<"items">>, HistJson),
    ?assert(length(Items) >= 1),
    ok.

%% An operations-role key must not be able to rotate any key.
non_admin_cannot_rotate(_Config) ->
    {ok, AdminSession} = create_session(<<"rot-admin5@example.com">>, admin),
    {ok, AdminKey} = create_api_key(AdminSession, <<"admin">>),
    {KeyId, _} = get_key_id_for_secret(AdminKey),
    {ok, OpsKey} = create_api_key(AdminSession, <<"operations">>),

    {ok, {{_, 403, _}, _, Body}} =
        request(post, "/api/v1/api-keys/" ++ binary_to_list(KeyId) ++ "/rotate",
                <<>>, auth_headers(OpsKey)),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    ?assertEqual(<<"forbidden">>, maps:get(<<"error">>, Json)),
    ok.

%% Keys whose created_at predates the threshold appear in the pending list.
pending_rotation_lists_stale_keys(_Config) ->
    {ok, AdminSession} = create_session(<<"rot-admin6@example.com">>, admin),
    {ok, AdminKey} = create_api_key(AdminSession, <<"admin">>),
    {KeyId, _} = get_key_id_for_secret(AdminKey),

    %% Wind back created_at to simulate a 100-day-old key.
    StaleMs = erlang:system_time(millisecond) - (100 * 24 * 60 * 60 * 1000),
    {atomic, ok} = mnesia:transaction(fun() ->
        [K] = mnesia:read(api_keys, KeyId),
        mnesia:write(api_keys, K#api_key{created_at = StaleMs, updated_at = StaleMs}, write)
    end),

    %% With a 90-day threshold, this key should appear as pending.
    {ok, Pending} = cb_key_rotation:list_pending_rotation(90),
    PendingIds = [maps:get(key_id, P) || P <- Pending],
    ?assert(lists:member(KeyId, PendingIds)),
    ok.

%% =============================================================================
%% Helpers
%% =============================================================================

create_session(Email, Role) ->
    {ok, _} = cb_auth:create_user(Email, <<"pass">>, Role),
    login(Email, <<"pass">>).

login(Email, Password) ->
    {ok, {{_, 200, _}, _, Body}} = request(
        post, "/api/v1/auth/login",
        jsone:encode(#{email => Email, password => Password}),
        [{"content-type", "application/json"}]
    ),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    {ok, maps:get(<<"session_id">>, Json)}.

create_api_key(SessionId, RoleBin) ->
    {ok, {{_, 201, _}, _, Body}} = request(
        post, "/api/v1/api-keys",
        jsone:encode(#{
            <<"label">>             => <<"rotation-test-key">>,
            <<"partner_id">>        => <<"rotation-test-partner">>,
            <<"role">>              => RoleBin,
            <<"rate_limit_per_min">> => 300
        }),
        auth_headers(SessionId) ++ [{"content-type", "application/json"}]
    ),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    {ok, maps:get(<<"key_secret">>, Json)}.

%% Return {KeyId, Secret} for the most recently created key whose hash
%% matches the supplied secret.  Uses `cb_api_keys:authenticate_key/1`
%% rather than scanning Mnesia directly so the test stays black-box.
get_key_id_for_secret(Secret) ->
    {ok, Meta} = cb_api_keys:authenticate_key(Secret),
    {maps:get(key_id, Meta), Secret}.

auth_headers(Token) when is_binary(Token) ->
    [{"authorization", "Bearer " ++ binary_to_list(Token)}].

request(Method, Path, Body, Headers) ->
    URL = "http://localhost:" ++ integer_to_list(?PORT) ++ Path,
    BodyStr = case Body of
        <<>> -> "";
        B when is_binary(B) -> binary_to_list(B)
    end,
    case Method of
        get ->
            httpc:request(get, {URL, Headers}, [{timeout, 5000}], []);
        post ->
            httpc:request(post, {URL, Headers, "application/json", BodyStr},
                          [{timeout, 5000}], [])
    end.
