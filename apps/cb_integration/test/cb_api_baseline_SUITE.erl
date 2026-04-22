%% @doc P0-S4 API and Security Baseline Test Suite
%%
%% Covers TASK-016 through TASK-020:
%%   016 - OpenAPI spec served at /api/v1/openapi.json
%%   017 - Standard error envelope on validation failures
%%   018 - Role-aware authorization guard
%%   019 - Rate limiting (unit) and /metrics endpoint
%%   020 - Webhook event emission for transaction state changes

-module(cb_api_baseline_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").
-include_lib("cb_events/include/cb_events.hrl").

-export([all/0, groups/0, init_per_suite/1, end_per_suite/1,
         init_per_testcase/2, end_per_testcase/2]).

%% TASK-016: OpenAPI spec
-export([openapi_spec_returns_200/1, openapi_spec_has_required_keys/1]).

%% TASK-017: Error envelope
-export([missing_required_field_returns_422/1, invalid_json_returns_400/1,
         deposit_channel_field_forwarded/1,
         withdrawal_limit_error_returns_422/1]).

%% TASK-018: Role-aware auth
-export([read_only_cannot_post_transactions/1, operations_can_post_transactions/1,
         unauthenticated_returns_401/1, admin_can_access_all/1]).

%% TASK-019: Metrics and rate limiter
-export([metrics_endpoint_returns_200/1, metrics_contains_vm_keys/1,
         rate_limiter_allows_under_limit/1, rate_limiter_blocks_over_limit/1,
         rate_limiter_resets_window/1]).

%% TASK-020: Webhook event emission
-export([deposit_writes_outbox_event/1, withdrawal_writes_outbox_event/1,
         transfer_writes_outbox_event/1, reversal_writes_outbox_event/1,
         outbox_events_delivered_to_subscriber/1]).

-define(PORT, 18082).

all() ->
    [{group, openapi}, {group, error_envelope}, {group, role_auth},
     {group, metrics}, {group, webhook_events}].

groups() ->
    [
        {openapi, [sequence], [openapi_spec_returns_200, openapi_spec_has_required_keys]},
        {error_envelope, [sequence],
            [missing_required_field_returns_422, invalid_json_returns_400,
             deposit_channel_field_forwarded, withdrawal_limit_error_returns_422]},
        {role_auth, [sequence],
            [unauthenticated_returns_401, read_only_cannot_post_transactions,
             operations_can_post_transactions, admin_can_access_all]},
        {metrics, [sequence],
            [metrics_endpoint_returns_200, metrics_contains_vm_keys,
             rate_limiter_allows_under_limit, rate_limiter_blocks_over_limit,
             rate_limiter_resets_window]},
        {webhook_events, [sequence],
            [deposit_writes_outbox_event, withdrawal_writes_outbox_event,
             transfer_writes_outbox_event, reversal_writes_outbox_event,
             outbox_events_delivered_to_subscriber]}
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
        [party, party_audit, account, transaction, ledger_entry,
         auth_user, auth_session, audit_log,
         event_outbox, webhook_subscription, webhook_delivery,
         chart_account, balance_snapshot, account_hold]),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

%%% ============================================================
%%% TASK-016: OpenAPI spec
%%% ============================================================

openapi_spec_returns_200(_Config) ->
    {ok, {{_, 200, _}, _Headers, _Body}} = request(get, "/api/v1/openapi.json", <<>>, []),
    ok.

openapi_spec_has_required_keys(_Config) ->
    {ok, {{_, 200, _}, _Headers, Body}} = request(get, "/api/v1/openapi.json", <<>>, []),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    ?assert(maps:is_key(<<"openapi">>, Json)),
    ?assert(maps:is_key(<<"info">>, Json)),
    ?assert(maps:is_key(<<"paths">>, Json)),
    Paths = maps:get(<<"paths">>, Json),
    %% Core release-blocking paths must be present
    ?assert(maps:is_key(<<"/api/v1/parties">>, Paths)),
    ?assert(maps:is_key(<<"/api/v1/accounts">>, Paths)),
    ?assert(maps:is_key(<<"/api/v1/transactions/deposit">>, Paths)),
    ?assert(maps:is_key(<<"/api/v1/transactions/transfer">>, Paths)),
    ?assert(maps:is_key(<<"/api/v1/transactions/withdraw">>, Paths)),
    ok.

%%% ============================================================
%%% TASK-017: Error envelope
%%% ============================================================

missing_required_field_returns_422(_Config) ->
    {ok, Session} = create_ops_session(),
    %% POST deposit with missing fields
    {ok, {{_, Status, _}, _Headers, Body}} = request(
        post,
        "/api/v1/transactions/deposit",
        jsone:encode(#{<<"amount">> => 1000}),
        [{"content-type", "application/json"} | auth_headers(Session)]
    ),
    ?assertEqual(422, Status),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    ?assert(maps:is_key(<<"error">>, Json)),
    ?assert(maps:is_key(<<"message">>, Json)),
    ok.

invalid_json_returns_400(_Config) ->
    {ok, Session} = create_ops_session(),
    {ok, {{_, Status, _}, _Headers, Body}} = request(
        post,
        "/api/v1/transactions/deposit",
        <<"not json at all">>,
        [{"content-type", "application/json"} | auth_headers(Session)]
    ),
    ?assertEqual(400, Status),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    ?assertEqual(<<"invalid_json">>, maps:get(<<"error">>, Json)),
    ok.

deposit_channel_field_forwarded(_Config) ->
    {ok, Session} = create_ops_session(),
    {ok, Party} = cb_party:create_party(<<"CH Party">>, <<"ch@example.com">>),
    {ok, Acc} = cb_accounts:create_account(Party#party.party_id, <<"Main">>, 'USD'),
    {ok, {{_, 201, _}, _Headers, Body}} = request(
        post,
        "/api/v1/transactions/deposit",
        jsone:encode(#{
            <<"idempotency_key">> => <<"ch-dep-1">>,
            <<"dest_account_id">> => Acc#account.account_id,
            <<"amount">> => 1000,
            <<"currency">> => <<"USD">>,
            <<"description">> => <<"Cash">>,
            <<"channel">> => <<"cash">>
        }),
        [{"content-type", "application/json"} | auth_headers(Session)]
    ),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    ?assertEqual(<<"cash">>, maps:get(<<"channel">>, Json, undefined)),
    ok.

withdrawal_limit_error_returns_422(_Config) ->
    {ok, Session} = create_ops_session(),
    {ok, Party} = cb_party:create_party(<<"WL Party">>, <<"wl@example.com">>),
    {ok, Acc} = cb_accounts:create_account(Party#party.party_id, <<"Main">>, 'USD'),
    ok = cb_accounts:set_withdrawal_limit(Acc#account.account_id, 100),
    {ok, _} = cb_payments:deposit(<<"wl-seed-1">>, Acc#account.account_id, 5000, 'USD', <<"Seed">>),
    {ok, {{_, Status, _}, _Headers, Body}} = request(
        post,
        "/api/v1/transactions/withdraw",
        jsone:encode(#{
            <<"idempotency_key">> => <<"wl-wdl-1">>,
            <<"source_account_id">> => Acc#account.account_id,
            <<"amount">> => 500,
            <<"currency">> => <<"USD">>,
            <<"description">> => <<"Over limit">>
        }),
        [{"content-type", "application/json"} | auth_headers(Session)]
    ),
    ?assertEqual(422, Status),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    ?assertEqual(<<"withdrawal_limit_exceeded">>, maps:get(<<"error">>, Json)),
    ok.

%%% ============================================================
%%% TASK-018: Role-aware auth
%%% ============================================================

unauthenticated_returns_401(_Config) ->
    {ok, {{_, 401, _}, _Headers, Body}} = request(
        post, "/api/v1/transactions/deposit",
        jsone:encode(#{<<"foo">> => <<"bar">>}),
        [{"content-type", "application/json"}]
    ),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    ?assertEqual(<<"unauthorized">>, maps:get(<<"error">>, Json)),
    ok.

read_only_cannot_post_transactions(_Config) ->
    {ok, _} = cb_auth:create_user(<<"ro@example.com">>, <<"pass">>, read_only),
    {ok, {session_id, SessionId}} = login(<<"ro@example.com">>, <<"pass">>),
    {ok, {{_, Status, _}, _Headers, Body}} = request(
        post, "/api/v1/transactions/deposit",
        jsone:encode(#{<<"foo">> => <<"bar">>}),
        [{"content-type", "application/json"} | auth_headers(SessionId)]
    ),
    ?assertEqual(403, Status),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    ?assertEqual(<<"forbidden">>, maps:get(<<"error">>, Json)),
    ok.

operations_can_post_transactions(_Config) ->
    {ok, Session} = create_ops_session(),
    {ok, Party} = cb_party:create_party(<<"Ops Party">>, <<"ops_party@example.com">>),
    {ok, Acc} = cb_accounts:create_account(Party#party.party_id, <<"Main">>, 'USD'),
    {ok, {{_, Status, _}, _Headers, _Body}} = request(
        post,
        "/api/v1/transactions/deposit",
        jsone:encode(#{
            <<"idempotency_key">> => <<"ops-dep-1">>,
            <<"dest_account_id">> => Acc#account.account_id,
            <<"amount">> => 500,
            <<"currency">> => <<"USD">>,
            <<"description">> => <<"Test">>
        }),
        [{"content-type", "application/json"} | auth_headers(Session)]
    ),
    ?assertEqual(201, Status),
    ok.

admin_can_access_all(_Config) ->
    {ok, _} = cb_auth:create_user(<<"admin2@example.com">>, <<"pass">>, admin),
    {ok, {session_id, SessionId}} = login(<<"admin2@example.com">>, <<"pass">>),
    %% Admin can GET accounts
    {ok, {{_, GetStatus, _}, _Headers, _}} = request(
        get, "/api/v1/accounts", <<>>, auth_headers(SessionId)
    ),
    ?assertEqual(200, GetStatus),
    ok.

%%% ============================================================
%%% TASK-019: Metrics and rate limiter
%%% ============================================================

metrics_endpoint_returns_200(_Config) ->
    {ok, {{_, 200, _}, _Headers, _Body}} = request(get, "/metrics", <<>>, []),
    ok.

metrics_contains_vm_keys(_Config) ->
    {ok, {{_, 200, _}, _Headers, Body}} = request(get, "/metrics", <<>>, []),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    ?assert(maps:is_key(<<"process_count">>, Json)),
    ?assert(maps:is_key(<<"memory_total">>, Json)),
    ?assert(maps:is_key(<<"uptime_ms">>, Json)),
    ok.

rate_limiter_allows_under_limit(_Config) ->
    %% Reset limiter state for IP 127.0.0.1
    cb_rate_limiter:reset(<<"127.0.0.1">>),
    %% Well under the limit - should all be allowed
    Results = [cb_rate_limiter:check_and_increment(<<"127.0.0.1">>) || _ <- lists:seq(1, 5)],
    ?assert(lists:all(fun(R) -> R =:= allow end, Results)),
    ok.

rate_limiter_blocks_over_limit(_Config) ->
    %% Set a very low limit for this test
    TestKey = <<"test-ip-block">>,
    cb_rate_limiter:reset(TestKey),
    %% Override the limit by hitting it enough times
    Limit = cb_rate_limiter:get_limit(),
    lists:foreach(fun(_) -> cb_rate_limiter:check_and_increment(TestKey) end,
                  lists:seq(1, Limit)),
    %% Next request should be denied
    ?assertEqual(deny, cb_rate_limiter:check_and_increment(TestKey)),
    ok.

rate_limiter_resets_window(_Config) ->
    TestKey = <<"test-ip-reset">>,
    cb_rate_limiter:reset(TestKey),
    Limit = cb_rate_limiter:get_limit(),
    lists:foreach(fun(_) -> cb_rate_limiter:check_and_increment(TestKey) end,
                  lists:seq(1, Limit)),
    ?assertEqual(deny, cb_rate_limiter:check_and_increment(TestKey)),
    %% Force-reset (simulates window expiry)
    cb_rate_limiter:reset(TestKey),
    ?assertEqual(allow, cb_rate_limiter:check_and_increment(TestKey)),
    ok.

%%% ============================================================
%%% TASK-020: Webhook event emission for transaction state changes
%%% ============================================================

deposit_writes_outbox_event(_Config) ->
    mnesia:clear_table(event_outbox),
    {ok, Party} = cb_party:create_party(<<"Evt Party 1">>, <<"evt1@example.com">>),
    {ok, Acc} = cb_accounts:create_account(Party#party.party_id, <<"Main">>, 'USD'),
    {ok, _} = cb_payments:deposit(<<"evt-dep-1">>, Acc#account.account_id, 1000, 'USD', <<"Dep">>),
    Events = pending_events(),
    ?assert(lists:any(fun(E) -> E#event_outbox.event_type =:= <<"transaction.posted">> end, Events)),
    ok.

withdrawal_writes_outbox_event(_Config) ->
    mnesia:clear_table(event_outbox),
    {ok, Party} = cb_party:create_party(<<"Evt Party 2">>, <<"evt2@example.com">>),
    {ok, Acc} = cb_accounts:create_account(Party#party.party_id, <<"Main">>, 'USD'),
    {ok, _} = cb_payments:deposit(<<"evt-seed-2">>, Acc#account.account_id, 5000, 'USD', <<"Seed">>),
    mnesia:clear_table(event_outbox),
    {ok, _} = cb_payments:withdraw(<<"evt-wdl-1">>, Acc#account.account_id, 500, 'USD', <<"Wdl">>),
    Events = pending_events(),
    ?assert(lists:any(fun(E) -> E#event_outbox.event_type =:= <<"transaction.posted">> end, Events)),
    ok.

transfer_writes_outbox_event(_Config) ->
    mnesia:clear_table(event_outbox),
    {ok, Party} = cb_party:create_party(<<"Evt Party 3">>, <<"evt3@example.com">>),
    {ok, SrcAcc} = cb_accounts:create_account(Party#party.party_id, <<"Src">>, 'USD'),
    {ok, DstAcc} = cb_accounts:create_account(Party#party.party_id, <<"Dst">>, 'USD'),
    {ok, _} = cb_payments:deposit(<<"evt-seed-3">>, SrcAcc#account.account_id, 5000, 'USD', <<"Seed">>),
    mnesia:clear_table(event_outbox),
    {ok, _} = cb_payments:transfer(<<"evt-xfer-1">>,
        SrcAcc#account.account_id, DstAcc#account.account_id,
        500, 'USD', <<"Transfer">>),
    Events = pending_events(),
    ?assert(lists:any(fun(E) -> E#event_outbox.event_type =:= <<"transaction.posted">> end, Events)),
    ok.

reversal_writes_outbox_event(_Config) ->
    mnesia:clear_table(event_outbox),
    {ok, Party} = cb_party:create_party(<<"Evt Party 4">>, <<"evt4@example.com">>),
    {ok, Acc} = cb_accounts:create_account(Party#party.party_id, <<"Main">>, 'USD'),
    {ok, Txn} = cb_payments:deposit(<<"evt-dep-4">>, Acc#account.account_id, 5000, 'USD', <<"Dep">>),
    mnesia:clear_table(event_outbox),
    {ok, _} = cb_payments:reverse_transaction(Txn#transaction.txn_id),
    Events = pending_events(),
    ?assert(lists:any(fun(E) -> E#event_outbox.event_type =:= <<"transaction.reversed">> end, Events)),
    ok.

outbox_events_delivered_to_subscriber(_Config) ->
    mnesia:clear_table(event_outbox),
    mnesia:clear_table(webhook_subscription),
    mnesia:clear_table(webhook_delivery),
    %% Create subscription for all events
    {ok, _Sub} = cb_webhooks:create_subscription(<<"https://example.com/hook">>, <<"*">>),
    {ok, Party} = cb_party:create_party(<<"Evt Party 5">>, <<"evt5@example.com">>),
    {ok, Acc} = cb_accounts:create_account(Party#party.party_id, <<"Main">>, 'USD'),
    {ok, _} = cb_payments:deposit(<<"evt-dep-5">>, Acc#account.account_id, 1000, 'USD', <<"Dep">>),
    %% Trigger processing (will fail HTTP delivery to example.com but creates delivery record)
    ok = cb_webhooks:process_pending(),
    Deliveries = cb_webhooks:list_deliveries(),
    ?assert(length(Deliveries) >= 1),
    ok.

%%% ============================================================
%%% Helpers
%%% ============================================================

create_ops_session() ->
    Email = <<"ops_", (integer_to_binary(erlang:unique_integer([positive])))/binary, "@example.com">>,
    {ok, _} = cb_auth:create_user(Email, <<"pass">>, operations),
    login(Email, <<"pass">>).

login(Email, Password) ->
    {ok, {{_, 200, _}, _Headers, Body}} = request(
        post, "/api/v1/auth/login",
        jsone:encode(#{email => Email, password => Password}),
        [{"content-type", "application/json"}]
    ),
    {ok, Json, _} = jsone:try_decode(list_to_binary(Body)),
    SessionId = maps:get(<<"session_id">>, Json),
    {ok, {session_id, SessionId}}.

auth_headers({session_id, SessionId}) ->
    auth_headers(SessionId);
auth_headers(SessionId) when is_binary(SessionId) ->
    [{"authorization", "Bearer " ++ binary_to_list(SessionId)}].

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
                          [{timeout, 5000}], []);
        delete ->
            httpc:request(delete, {URL, Headers}, [{timeout, 5000}], [])
    end.

pending_events() ->
    F = fun() ->
        mnesia:select(event_outbox, [{#event_outbox{_ = '_'}, [], ['$_']}])
    end,
    case mnesia:transaction(F) of
        {atomic, Events} -> Events;
        {aborted, _}     -> []
    end.
