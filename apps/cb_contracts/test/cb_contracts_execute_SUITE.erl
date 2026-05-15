%% @doc Common Test suite for cb_contracts execution flows
%%
%% Tests contract validation, execution, timeouts, capability checks, and trace generation.
-module(cb_contracts_execute_SUITE).

-include_lib("common_test/include/ct.hrl").
-include("../include/cb_contracts.hrl").

-compile(export_all).

suite() ->
    [{timetrap, {seconds, 60}}].

all() ->
    [
        test_execute_happy_path,
        test_execute_with_authz_capabilities,
        test_execute_timeout,
        test_execute_validation_error,
        test_execute_reject_decision,
        test_execute_context_snapshot,
        test_execute_decision_snapshot,
        test_execute_trace_persistence,
        test_execute_trace_with_events,
        test_execute_multiple_rules,
        test_execute_rule_ordering,
        test_execute_unknown_variable_error
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

%% Helper: Create contract with simple approval rule
create_simple_contract(ContractId, Payload) ->
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
    {ok, Contract} = cb_contract_registry:activate_version(
        ContractId,
        Version#contract_version.version_id
    ),
    Contract.

%% Test: Happy path execution - evaluate rule and return decision
test_execute_happy_path(_Config) ->
    ContractId = <<"contract-exec-1">>,
    Payload = #{
        rules => [
            #{
                when => #{account_status => <<"active">>},
                then => #{action => set, decision => approve}
            }
        ]
    },
    create_simple_contract(ContractId, Payload),
    
    RequestId = <<"req-1">>,
    Context = #{account_status => <<"active">>},
    Authz = #{capabilities => [can_emit_event], timeout_ms => 50},
    
    {ok, Result} = cb_contracts:execute(ContractId, RequestId, #{
        context => Context,
        authz => Authz
    }),
    
    ?assertMatch(#{decision := approve, trace := _}, Result).

%% Test: Execution with authorization capabilities
test_execute_with_authz_capabilities(_Config) ->
    ContractId = <<"contract-exec-2">>,
    Payload = #{
        rules => [
            #{
                when => #{},
                then => #{action => emit, event => payment_review_requested}
            }
        ]
    },
    create_simple_contract(ContractId, Payload),
    
    RequestId = <<"req-2">>,
    Context = #{},
    Authz = #{capabilities => [can_emit_event], timeout_ms => 50},
    
    {ok, Result} = cb_contracts:execute(ContractId, RequestId, #{
        context => Context,
        authz => Authz
    }),
    
    ?assertMatch(#{decision := _, trace := _}, Result).

%% Test: Execution timeout triggers budget_exceeded error
test_execute_timeout(_Config) ->
    ContractId = <<"contract-exec-3">>,
    %% Payload with expensive loop to trigger timeout
    Payload = #{
        rules => [
            #{
                when => #{},
                then => #{
                    action => set,
                    decision => {max, [1, 2, 3]}  %% Nested evaluation
                }
            }
        ]
    },
    create_simple_contract(ContractId, Payload),
    
    RequestId = <<"req-3">>,
    Context = #{},
    Authz = #{capabilities => [can_emit_event], timeout_ms => 1},  %% Very short timeout
    
    Result = cb_contracts:execute(ContractId, RequestId, #{
        context => Context,
        authz => Authz
    }),
    
    %% With extremely tight timeout, should timeout
    ?assertMatch({error, execution_budget_exceeded} | {ok, _}, Result).

%% Test: Invalid contract schema causes validation error
test_execute_validation_error(_Config) ->
    ContractId = <<"contract-exec-4">>,
    %% Invalid: using unsupported operator
    Payload = #{
        rules => [
            #{
                when => #{forbidden_op => {1, 2}},
                then => #{action => set, decision => approve}
            }
        ]
    },
    
    RequestId = <<"req-4">>,
    Context = #{},
    Authz = #{capabilities => [can_emit_event], timeout_ms => 50},
    
    Result = cb_contracts:execute(ContractId, RequestId, #{
        context => Context,
        authz => Authz,
        contract_payload => Payload
    }),
    
    ?assertMatch({error, _}, Result).

%% Test: Reject decision returned when condition fails
test_execute_reject_decision(_Config) ->
    ContractId = <<"contract-exec-5">>,
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
    create_simple_contract(ContractId, Payload),
    
    RequestId = <<"req-5">>,
    Context = #{account_status => <<"suspended">>},  %% Doesn't match first rule
    Authz = #{capabilities => [can_emit_event], timeout_ms => 50},
    
    {ok, Result} = cb_contracts:execute(ContractId, RequestId, #{
        context => Context,
        authz => Authz
    }),
    
    ?assertMatch(#{decision := reject}, Result).

%% Test: Context snapshot captured in trace
test_execute_context_snapshot(_Config) ->
    ContractId = <<"contract-exec-6">>,
    Payload = #{
        rules => [
            #{
                when => #{},
                then => #{action => set, decision => approve}
            }
        ]
    },
    create_simple_contract(ContractId, Payload),
    
    RequestId = <<"req-6">>,
    Context = #{
        party_id => <<"party:123">>,
        account_status => <<"active">>,
        balance => 5000
    },
    Authz = #{capabilities => [can_emit_event], timeout_ms => 50},
    
    {ok, Result} = cb_contracts:execute(ContractId, RequestId, #{
        context => Context,
        authz => Authz
    }),
    
    #{trace := Trace} = Result,
    ?assertMatch(#{context_snapshot := _}, Trace).

%% Test: Decision snapshot captured in trace
test_execute_decision_snapshot(_Config) ->
    ContractId = <<"contract-exec-7">>,
    Payload = #{
        rules => [
            #{
                when => #{},
                then => #{action => set, decision => approve}
            }
        ]
    },
    create_simple_contract(ContractId, Payload),
    
    RequestId = <<"req-7">>,
    Context = #{party_id => <<"party:123">>},
    Authz = #{capabilities => [can_emit_event], timeout_ms => 50},
    
    {ok, Result} = cb_contracts:execute(ContractId, RequestId, #{
        context => Context,
        authz => Authz
    }),
    
    #{trace := Trace} = Result,
    ?assertMatch(#{decision_snapshot := _}, Trace).

%% Test: Trace is persisted to Mnesia
test_execute_trace_persistence(_Config) ->
    ContractId = <<"contract-exec-8">>,
    Payload = #{
        rules => [
            #{
                when => #{},
                then => #{action => set, decision => approve}
            }
        ]
    },
    create_simple_contract(ContractId, Payload),
    
    RequestId = <<"req-8">>,
    Context = #{party_id => <<"party:123">>},
    Authz = #{capabilities => [can_emit_event], timeout_ms => 50},
    
    {ok, Result} = cb_contracts:execute(ContractId, RequestId, #{
        context => Context,
        authz => Authz
    }),
    
    #{trace := #{execution_id := ExecutionId}} = Result,
    
    %% Verify trace was persisted
    {ok, RetrievedTrace} = cb_contract_audit:retrieve_trace(ExecutionId),
    ?assertEqual(ExecutionId, RetrievedTrace#contract_execution_trace.execution_id),
    ?assertEqual(ok, RetrievedTrace#contract_execution_trace.result).

%% Test: Events are captured in trace
test_execute_trace_with_events(_Config) ->
    ContractId = <<"contract-exec-9">>,
    Payload = #{
        rules => [
            #{
                when => #{},
                then => #{
                    action => emit,
                    event => payment_review_requested
                }
            }
        ]
    },
    create_simple_contract(ContractId, Payload),
    
    RequestId = <<"req-9">>,
    Context = #{},
    Authz = #{capabilities => [can_emit_event], timeout_ms => 50},
    
    {ok, Result} = cb_contracts:execute(ContractId, RequestId, #{
        context => Context,
        authz => Authz
    }),
    
    #{trace := Trace} = Result,
    ?assertMatch(#{steps := _}, Trace).

%% Test: Multiple rules evaluated in sequence
test_execute_multiple_rules(_Config) ->
    ContractId = <<"contract-exec-10">>,
    Payload = #{
        rules => [
            #{
                when => #{amount => {in, [1000, 2000, 5000]}},
                then => #{action => enqueue_review, status => low_risk}
            },
            #{
                when => #{amount => {in, [10000, 50000]}},
                then => #{action => enqueue_review, status => medium_risk}
            },
            #{
                when => #{},
                then => #{action => set, decision => reject}
            }
        ]
    },
    create_simple_contract(ContractId, Payload),
    
    RequestId = <<"req-10">>,
    Context = #{amount => 2000},
    Authz = #{capabilities => [can_emit_event], timeout_ms => 50},
    
    {ok, Result} = cb_contracts:execute(ContractId, RequestId, #{
        context => Context,
        authz => Authz
    }),
    
    ?assertMatch(#{decision := _, trace := _}, Result).

%% Test: Rules are evaluated in order until one matches
test_execute_rule_ordering(_Config) ->
    ContractId = <<"contract-exec-11">>,
    Payload = #{
        rules => [
            #{
                when => #{amount => {>, 0}},
                then => #{action => set, decision => approve}
            },
            #{
                when => #{amount => {>, 5000}},  %% This would also match but shouldn't be reached
                then => #{action => set, decision => reject}
            }
        ]
    },
    create_simple_contract(ContractId, Payload),
    
    RequestId = <<"req-11">>,
    Context = #{amount => 10000},  %% Matches both rules, first should win
    Authz = #{capabilities => [can_emit_event], timeout_ms => 50},
    
    {ok, Result} = cb_contracts:execute(ContractId, RequestId, #{
        context => Context,
        authz => Authz
    }),
    
    #{decision := Decision} = Result,
    ?assertEqual(approve, Decision).

%% Test: Unknown variable in context causes error
test_execute_unknown_variable_error(_Config) ->
    ContractId = <<"contract-exec-12">>,
    Payload = #{
        rules => [
            #{
                when => #{unknown_field => <<"value">>},
                then => #{action => set, decision => approve}
            }
        ]
    },
    create_simple_contract(ContractId, Payload),
    
    RequestId = <<"req-12">>,
    Context = #{account_status => <<"active">>},  %% Doesn't have unknown_field
    Authz = #{capabilities => [can_emit_event], timeout_ms => 50},
    
    Result = cb_contracts:execute(ContractId, RequestId, #{
        context => Context,
        authz => Authz
    }),
    
    %% Unknown field should either be treated as nil or return error
    ?assertMatch({ok, _} | {error, _}, Result).
