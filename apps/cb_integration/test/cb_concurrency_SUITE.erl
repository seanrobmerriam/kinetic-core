%% @doc CT suite for cb_concurrency (TASK-067).
-module(cb_concurrency_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    all/0,
    init_per_suite/1,
    end_per_suite/1,
    init_per_testcase/2,
    end_per_testcase/2
]).

-export([
    test_acquire_creates_token/1,
    test_acquire_idempotent/1,
    test_latest_version/1,
    test_latest_version_not_found/1,
    test_cas_update_success/1,
    test_cas_update_conflict/1,
    test_cas_update_increments_version/1,
    test_resolve_conflict_reject/1,
    test_resolve_conflict_last_write_wins/1,
    test_list_tokens/1
]).

all() ->
    [test_acquire_creates_token,
     test_acquire_idempotent,
     test_latest_version,
     test_latest_version_not_found,
     test_cas_update_success,
     test_cas_update_conflict,
     test_cas_update_increments_version,
     test_resolve_conflict_reject,
     test_resolve_conflict_last_write_wins,
     test_list_tokens].

init_per_suite(Config) ->
    ok = mnesia:start(),
    Tables = [cluster_node, version_token, scaling_rule, capacity_sample, recovery_checkpoint],
    [catch mnesia:delete_table(T) || T <- Tables],
    ok = cb_schema:create_tables(),
    Config.

end_per_suite(_Config) ->
    mnesia:stop(),
    ok.

init_per_testcase(_TestCase, Config) ->
    {atomic, ok} = mnesia:clear_table(version_token),
    Config.

end_per_testcase(_TestCase, _Config) -> ok.

%%--------------------------------------------------------------------
%% Test cases
%%--------------------------------------------------------------------

test_acquire_creates_token(_Config) ->
    {ok, 0} = cb_concurrency:acquire_token(<<"account">>, <<"acc-1">>).

test_acquire_idempotent(_Config) ->
    {ok, 0} = cb_concurrency:acquire_token(<<"account">>, <<"acc-2">>),
    {ok, 0} = cb_concurrency:acquire_token(<<"account">>, <<"acc-2">>).

test_latest_version(_Config) ->
    {ok, 0} = cb_concurrency:acquire_token(<<"account">>, <<"acc-3">>),
    {ok, 0} = cb_concurrency:latest_version({<<"account">>, <<"acc-3">>}).

test_latest_version_not_found(_Config) ->
    {error, not_found} = cb_concurrency:latest_version({<<"account">>, <<"no-such">>}).

test_cas_update_success(_Config) ->
    Ref = {<<"account">>, <<"acc-cas-ok">>},
    {ok, 0} = cb_concurrency:acquire_token(<<"account">>, <<"acc-cas-ok">>),
    ok = cb_concurrency:cas_update(Ref, 0, fun(_V) -> ok end),
    {ok, 1} = cb_concurrency:latest_version(Ref).

test_cas_update_conflict(_Config) ->
    Ref = {<<"account">>, <<"acc-cas-conflict">>},
    {ok, 0} = cb_concurrency:acquire_token(<<"account">>, <<"acc-cas-conflict">>),
    {conflict, 0} = cb_concurrency:cas_update(Ref, 99, fun(_V) -> ok end).

test_cas_update_increments_version(_Config) ->
    Ref = {<<"loan">>, <<"loan-v-1">>},
    {ok, 0} = cb_concurrency:acquire_token(<<"loan">>, <<"loan-v-1">>),
    ok = cb_concurrency:cas_update(Ref, 0, fun(_) -> ok end),
    ok = cb_concurrency:cas_update(Ref, 1, fun(_) -> ok end),
    {ok, 2} = cb_concurrency:latest_version(Ref).

test_resolve_conflict_reject(_Config) ->
    Ref = {<<"account">>, <<"acc-reject">>},
    {ok, 0} = cb_concurrency:acquire_token(<<"account">>, <<"acc-reject">>),
    {conflict, 0} = cb_concurrency:resolve_conflict(Ref, reject, fun() -> ok end).

test_resolve_conflict_last_write_wins(_Config) ->
    Ref = {<<"account">>, <<"acc-lww">>},
    {ok, 0} = cb_concurrency:acquire_token(<<"account">>, <<"acc-lww">>),
    ok = cb_concurrency:resolve_conflict(Ref, last_write_wins, fun() -> ok end),
    {ok, 1} = cb_concurrency:latest_version(Ref).

test_list_tokens(_Config) ->
    {ok, _} = cb_concurrency:acquire_token(<<"payment">>, <<"p-1">>),
    {ok, _} = cb_concurrency:acquire_token(<<"payment">>, <<"p-2">>),
    {ok, _} = cb_concurrency:acquire_token(<<"loan">>,    <<"l-1">>),
    PayTokens = cb_concurrency:list_tokens(<<"payment">>),
    true = length(PayTokens) >= 2,
    LoanTokens = cb_concurrency:list_tokens(<<"loan">>),
    true = length(LoanTokens) >= 1.
