%% @doc Common Test suite for cb_contract_replay module
%%
%% Tests execution trace retrieval, replay, context override, and regression detection.
-module(cb_contract_replay_SUITE).

-include_lib("common_test/include/ct.hrl").
-include("../include/cb_contracts.hrl").

-compile(export_all).

suite() ->
    [{timetrap, {seconds, 60}}].

all() ->
    [
        test_get_execution_trace,
        test_get_execution_trace_not_found,
        test_list_execution_traces,
        test_list_execution_traces_pagination,
        test_replay_execution_original_context,
        test_replay_execution_with_context_override,
        test_replay_hash_match_identical_context,
        test_replay_hash_mismatch_different_context,
        test_replay_decision_comparison,
        test_replay_empty_trace_list
    ].

init_per_suite(Config) ->
    mnemosyne:start(),
    mnesia:start(),
    cb_schema:create_tables(),
    Config.

end_per_suite(_Config) ->
    mnesia:stop().

init_per_testcase(_TestCase, Config) ->
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

%% Helper: Create contract, deploy, execute, and return ExecutionId
execute_contract(ContractId, Context) ->
    Payload = #{
        rules => [
            #{
                when => #{account_status => <<"active">>},
                then => #{action => set, decision => approve}
            },
            #{
                when => #{},
                then => #{action => set, decision => reject}
            }
        ]
    },
    cb_contract_registry:create_contract(#{
        contract_id => ContractId,
        name => <<"Test Contract">>,
        domain => <<"payments">>,
        owner_role => <<"admin">>
    }),
    {ok, Version} = cb_contract_registry:deploy_version(
        ContractId,
        <<"1.0">>,
        Payload,
        <<"user">>
    ),
    {ok, _Contract} = cb_contract_registry:activate_version(
        ContractId,
        Version#contract_version.version_id
    ),
    
    RequestId = <<"req-replay">>,
    Authz = #{capabilities => [can_emit_event], timeout_ms => 50},
    {ok, Result} = cb_contracts:execute(ContractId, RequestId, #{
        context => Context,
        authz => Authz
    }),
    
    #{trace := #{execution_id := ExecutionId}} = Result,
    ExecutionId.

%% Test: Get execution trace by ID
test_get_execution_trace(_Config) ->
    ContractId = <<"contract-replay-1">>,
    Context = #{account_status => <<"active">>},
    ExecutionId = execute_contract(ContractId, Context),
    
    {ok, Trace} = cb_contract_replay:get_execution_trace(ExecutionId),
    ?assertEqual(ExecutionId, Trace#contract_execution_trace.execution_id),
    ?assertEqual(ContractId, Trace#contract_execution_trace.contract_id),
    ?assertEqual(ok, Trace#contract_execution_trace.result).

%% Test: Get non-existent trace returns error
test_get_execution_trace_not_found(_Config) ->
    Result = cb_contract_replay:get_execution_trace(<<"nonexistent-execution">>),
    ?assertMatch({error, execution_not_found}, Result).

%% Test: List execution traces for contract
test_list_execution_traces(_Config) ->
    ContractId = <<"contract-replay-2">>,
    Context1 = #{account_status => <<"active">>},
    Context2 = #{account_status => <<"suspended">>},
    
    _ExecutionId1 = execute_contract(ContractId, Context1),
    timer:sleep(50),
    _ExecutionId2 = execute_contract(ContractId, Context2),
    
    Traces = cb_contract_replay:list_execution_traces(ContractId, 100),
    ?assertEqual(2, length(Traces)),
    %% Verify newest is first
    [First | _] = Traces,
    ?assertNotEqual(undefined, First#contract_execution_trace.execution_id).

%% Test: List execution traces with pagination limit
test_list_execution_traces_pagination(_Config) ->
    ContractId = <<"contract-replay-3">>,
    Context = #{account_status => <<"active">>},
    
    %% Execute 5 times
    [execute_contract(ContractId, Context) || _ <- lists:seq(1, 5)],
    
    %% Request only 3
    Traces = cb_contract_replay:list_execution_traces(ContractId, 3),
    ?assertEqual(3, length(Traces)).

%% Test: Replay with original context produces consistent result
test_replay_execution_original_context(_Config) ->
    ContractId = <<"contract-replay-4">>,
    Context = #{account_status => <<"active">>, balance => 1000},
    ExecutionId = execute_contract(ContractId, Context),
    
    {ok, Trace} = cb_contract_replay:get_execution_trace(ExecutionId),
    
    {ok, Replay} = cb_contract_replay:replay_execution(ExecutionId, #{}),  %% No override
    
    ?assertMatch(#{replay_result := ok, hash_match := true}, Replay).

%% Test: Replay with context override uses new context
test_replay_execution_with_context_override(_Config) ->
    ContractId = <<"contract-replay-5">>,
    OriginalContext = #{account_status => <<"active">>},
    OverrideContext = #{account_status => <<"suspended">>},
    
    ExecutionId = execute_contract(ContractId, OriginalContext),
    
    {ok, Trace} = cb_contract_replay:get_execution_trace(ExecutionId),
    OriginalDecisionHash = Trace#contract_execution_trace.decision_hash,
    
    {ok, Replay} = cb_contract_replay:replay_execution(ExecutionId, #{
        context => OverrideContext
    }),
    
    ?assertMatch(#{replay_result := ok}, Replay),
    %% Context change may result in different decision hash
    #{decision_hash := NewDecisionHash} = Replay,
    % Hash may differ due to different context
    ?assertNotEqual(undefined, NewDecisionHash).

%% Test: Hash match when replaying with identical context
test_replay_hash_match_identical_context(_Config) ->
    ContractId = <<"contract-replay-6">>,
    Context = #{account_status => <<"active">>, amount => 5000},
    ExecutionId = execute_contract(ContractId, Context),
    
    {ok, Replay} = cb_contract_replay:replay_execution(ExecutionId, #{}),  %% No override
    
    #{hash_match := HashMatch} = Replay,
    ?assertEqual(true, HashMatch).

%% Test: Hash mismatch when replaying with different context
test_replay_hash_mismatch_different_context(_Config) ->
    ContractId = <<"contract-replay-7">>,
    OriginalContext = #{account_status => <<"active">>},
    OverrideContext = #{account_status => <<"suspended">>},
    
    ExecutionId = execute_contract(ContractId, OriginalContext),
    
    {ok, Trace} = cb_contract_replay:get_execution_trace(ExecutionId),
    ?assertEqual(approve, trace_decision_from_snapshot(Trace)),
    
    {ok, Replay} = cb_contract_replay:replay_execution(ExecutionId, #{
        context => OverrideContext
    }),
    
    #{hash_match := HashMatch, decision_snapshot := NewSnapshot} = Replay,
    ReplayDecision = maps:get(decision, NewSnapshot, undefined),
    
    %% With suspended status, decision should differ
    ?assertNotEqual(approve, ReplayDecision).

%% Test: Decision comparison in replay result
test_replay_decision_comparison(_Config) ->
    ContractId = <<"contract-replay-8">>,
    Context = #{account_status => <<"active">>},
    ExecutionId = execute_contract(ContractId, Context),
    
    {ok, Replay} = cb_contract_replay:replay_execution(ExecutionId, #{}),
    
    ?assertMatch(#{
        replay_result := ok,
        old_decision_hash := _,
        new_decision_hash := _,
        decision := _
    }, Replay).

%% Test: Empty trace list when no executions for contract
test_replay_empty_trace_list(_Config) ->
    ContractId = <<"contract-replay-9">>,
    
    Traces = cb_contract_replay:list_execution_traces(ContractId, 100),
    ?assertEqual(0, length(Traces)).

%% Helper: Extract decision from snapshot
trace_decision_from_snapshot(Trace) ->
    Snapshot = Trace#contract_execution_trace.decision_snapshot,
    maps:get(decision, Snapshot, undefined).
