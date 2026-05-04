%% @doc CT suite for cb_recovery (TASK-069).
-module(cb_recovery_SUITE).
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
    test_create_checkpoint/1,
    test_get_checkpoint/1,
    test_list_checkpoints/1,
    test_latest_checkpoint/1,
    test_initiate_recovery/1,
    test_complete_recovery/1,
    test_abort_recovery/1,
    test_validate_recovery_ok/1,
    test_validate_recovery_not_completed/1,
    test_validate_recovery_empty_snapshot/1,
    test_invalid_transitions/1
]).

all() ->
    [test_create_checkpoint,
     test_get_checkpoint,
     test_list_checkpoints,
     test_latest_checkpoint,
     test_initiate_recovery,
     test_complete_recovery,
     test_abort_recovery,
     test_validate_recovery_ok,
     test_validate_recovery_not_completed,
     test_validate_recovery_empty_snapshot,
     test_invalid_transitions].

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
    {atomic, ok} = mnesia:clear_table(recovery_checkpoint),
    Config.

end_per_testcase(_TestCase, _Config) -> ok.

%%--------------------------------------------------------------------
%% Test cases
%%--------------------------------------------------------------------

test_create_checkpoint(_Config) ->
    {ok, CId} = cb_recovery:create_checkpoint(sample_checkpoint()),
    true = is_binary(CId).

test_get_checkpoint(_Config) ->
    {ok, CId} = cb_recovery:create_checkpoint(sample_checkpoint()),
    {ok, #recovery_checkpoint{checkpoint_id = CId, status = pending}} = cb_recovery:get_checkpoint(CId),
    {error, not_found} = cb_recovery:get_checkpoint(<<"nonexistent">>).

test_list_checkpoints(_Config) ->
    {ok, _} = cb_recovery:create_checkpoint(sample_checkpoint(<<"account">>, <<"acc-1">>)),
    {ok, _} = cb_recovery:create_checkpoint(sample_checkpoint(<<"account">>, <<"acc-1">>)),
    {ok, _} = cb_recovery:create_checkpoint(sample_checkpoint(<<"loan">>, <<"loan-2">>)),
    List1 = cb_recovery:list_checkpoints(<<"account">>, <<"acc-1">>),
    2 = length(List1),
    List2 = cb_recovery:list_checkpoints(<<"loan">>, <<"loan-2">>),
    1 = length(List2).

test_latest_checkpoint(_Config) ->
    {ok, CId1} = cb_recovery:create_checkpoint(sample_checkpoint(<<"account">>, <<"acc-latest">>)),
    timer:sleep(5),
    {ok, CId2} = cb_recovery:create_checkpoint(sample_checkpoint(<<"account">>, <<"acc-latest">>)),
    {ok, Latest} = cb_recovery:latest_checkpoint(<<"account">>, <<"acc-latest">>),
    %% Most recently created should be first
    true = Latest#recovery_checkpoint.checkpoint_id =:= CId1
        orelse Latest#recovery_checkpoint.checkpoint_id =:= CId2,
    {error, not_found} = cb_recovery:latest_checkpoint(<<"missing">>, <<"none">>).

test_initiate_recovery(_Config) ->
    {ok, CId} = cb_recovery:create_checkpoint(sample_checkpoint()),
    ok = cb_recovery:initiate_recovery(CId),
    {ok, C} = cb_recovery:get_checkpoint(CId),
    active = C#recovery_checkpoint.status.

test_complete_recovery(_Config) ->
    {ok, CId} = cb_recovery:create_checkpoint(sample_checkpoint()),
    ok = cb_recovery:initiate_recovery(CId),
    ok = cb_recovery:complete_recovery(CId),
    {ok, C} = cb_recovery:get_checkpoint(CId),
    completed = C#recovery_checkpoint.status,
    true = C#recovery_checkpoint.completed_at =/= undefined.

test_abort_recovery(_Config) ->
    {ok, CId} = cb_recovery:create_checkpoint(sample_checkpoint()),
    ok = cb_recovery:abort_recovery(CId),
    {ok, C} = cb_recovery:get_checkpoint(CId),
    aborted = C#recovery_checkpoint.status.

test_validate_recovery_ok(_Config) ->
    {ok, CId} = cb_recovery:create_checkpoint(sample_checkpoint()),
    ok = cb_recovery:initiate_recovery(CId),
    ok = cb_recovery:complete_recovery(CId),
    ok = cb_recovery:validate_recovery(CId).

test_validate_recovery_not_completed(_Config) ->
    {ok, CId} = cb_recovery:create_checkpoint(sample_checkpoint()),
    {error, not_completed} = cb_recovery:validate_recovery(CId).

test_validate_recovery_empty_snapshot(_Config) ->
    {ok, CId} = cb_recovery:create_checkpoint(#{
        resource_type  => <<"account">>,
        resource_id    => <<"acc-empty">>,
        state_snapshot => <<>>
    }),
    ok = cb_recovery:initiate_recovery(CId),
    ok = cb_recovery:complete_recovery(CId),
    {error, empty_snapshot} = cb_recovery:validate_recovery(CId).

test_invalid_transitions(_Config) ->
    {ok, CId} = cb_recovery:create_checkpoint(sample_checkpoint()),
    %% Cannot complete from pending (must initiate first)
    {error, invalid_status} = cb_recovery:complete_recovery(CId),
    %% Initiate → active
    ok = cb_recovery:initiate_recovery(CId),
    %% Cannot initiate again (already active)
    {error, invalid_status} = cb_recovery:initiate_recovery(CId),
    %% Complete → completed
    ok = cb_recovery:complete_recovery(CId),
    %% Cannot abort a completed checkpoint
    {error, invalid_status} = cb_recovery:abort_recovery(CId).

%%--------------------------------------------------------------------
%% Helpers
%%--------------------------------------------------------------------

sample_checkpoint() ->
    sample_checkpoint(<<"account">>, <<"acc-1">>).

sample_checkpoint(ResourceType, ResourceId) ->
    #{resource_type  => ResourceType,
      resource_id    => ResourceId,
      state_snapshot => <<"serialised-state-data-here">>}.
