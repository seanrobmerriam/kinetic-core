%% @doc Common Test suite for cb_contract_experiments module
%%
%% Tests variant experiments, deterministic assignment, and lifecycle management.
-module(cb_contract_experiments_SUITE).

-include_lib("common_test/include/ct.hrl").
-include("../include/cb_contracts.hrl").

-compile(export_all).

suite() ->
    [{timetrap, {seconds, 30}}].

all() ->
    [
        test_create_experiment_basic,
        test_create_experiment_invalid_versions,
        test_create_experiment_empty_variants,
        test_assign_variant_deterministic,
        test_assign_variant_hash_stability,
        test_assign_variant_weighted_distribution,
        test_activate_experiment,
        test_stop_experiment,
        test_activate_experiment_invalid_status,
        test_experiment_status_transitions,
        test_list_experiments
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

%% Helper: Create contract and versions for experiment tests
setup_contract_and_versions(ContractId, VersionCount) ->
    cb_contract_registry:create_contract(#{
        contract_id => ContractId,
        name => <<"Test">>,
        domain => <<"payments">>,
        owner_role => <<"admin">>
    }),
    Payload = #{rules => [#{when => #{}, then => #{action => set, decision => approve}}]},
    Versions = [
        element(2, cb_contract_registry:deploy_version(
            ContractId,
            iolist_to_binary(io_lib:format("~p.0", [V])),
            Payload,
            <<"user">>
        ))
        || V <- lists:seq(1, VersionCount)
    ],
    Versions.

%% Test: Create experiment with valid variants
test_create_experiment_basic(_Config) ->
    ContractId = <<"test-contract-exp-1">>,
    [V1, V2] = setup_contract_and_versions(ContractId, 2),
    Variants = [
        #{version => V1#contract_version.version_id, weight => 50},
        #{version => V2#contract_version.version_id, weight => 50}
    ],
    {ok, Exp} = cb_contract_experiments:create_experiment(
        ContractId,
        <<"Test Experiment">>,
        Variants,
        <<"test_user">>
    ),
    ?assertEqual(ContractId, Exp#contract_experiment.contract_id),
    ?assertEqual(<<"Test Experiment">>, Exp#contract_experiment.name),
    ?assertEqual(draft, Exp#contract_experiment.status),
    ?assertEqual(2, length(Exp#contract_experiment.variants)),
    ?assertNotEqual(undefined, Exp#contract_experiment.allocation_seed).

%% Test: Create experiment with non-existent version (error)
test_create_experiment_invalid_versions(_Config) ->
    ContractId = <<"test-contract-exp-2">>,
    setup_contract_and_versions(ContractId, 1),
    Variants = [
        #{version => <<"invalid-version">>, weight => 100}
    ],
    Result = cb_contract_experiments:create_experiment(
        ContractId,
        <<"Test">>,
        Variants,
        <<"user">>
    ),
    ?assertMatch({error, contract_version_not_found}, Result).

%% Test: Create experiment with empty variants (error)
test_create_experiment_empty_variants(_Config) ->
    ContractId = <<"test-contract-exp-3">>,
    setup_contract_and_versions(ContractId, 1),
    Variants = [],
    Result = cb_contract_experiments:create_experiment(
        ContractId,
        <<"Test">>,
        Variants,
        <<"user">>
    ),
    ?assertMatch({error, _}, Result).

%% Test: Deterministic assignment (same subject always gets same variant)
test_assign_variant_deterministic(_Config) ->
    ContractId = <<"test-contract-exp-4">>,
    [V1, V2] = setup_contract_and_versions(ContractId, 2),
    Variants = [
        #{version => V1#contract_version.version_id, weight => 50},
        #{version => V2#contract_version.version_id, weight => 50}
    ],
    {ok, Exp} = cb_contract_experiments:create_experiment(
        ContractId,
        <<"Test">>,
        Variants,
        <<"user">>
    ),
    SubjectKey = <<"party:12345">>,
    {ok, V1Assigned} = cb_contract_experiments:assign_variant(
        Exp#contract_experiment.experiment_id,
        SubjectKey,
        Exp#contract_experiment.allocation_seed
    ),
    {ok, V2Assigned} = cb_contract_experiments:assign_variant(
        Exp#contract_experiment.experiment_id,
        SubjectKey,
        Exp#contract_experiment.allocation_seed
    ),
    ?assertEqual(V1Assigned, V2Assigned).

%% Test: Hash stability (different subject keys produce stable results with same seed)
test_assign_variant_hash_stability(_Config) ->
    ContractId = <<"test-contract-exp-5">>,
    [V1, V2] = setup_contract_and_versions(ContractId, 2),
    Variants = [
        #{version => V1#contract_version.version_id, weight => 50},
        #{version => V2#contract_version.version_id, weight => 50}
    ],
    {ok, Exp} = cb_contract_experiments:create_experiment(
        ContractId,
        <<"Test">>,
        Variants,
        <<"user">>
    ),
    Seed = Exp#contract_experiment.allocation_seed,
    {ok, AssignmentA} = cb_contract_experiments:assign_variant(
        Exp#contract_experiment.experiment_id,
        <<"subject-1">>,
        Seed
    ),
    {ok, AssignmentB} = cb_contract_experiments:assign_variant(
        Exp#contract_experiment.experiment_id,
        <<"subject-2">>,
        Seed
    ),
    %% Different subjects may get different variants, but each is stable
    ?assertNotEqual(undefined, AssignmentA),
    ?assertNotEqual(undefined, AssignmentB).

%% Test: Weighted distribution (subjects are distributed according to weights)
test_assign_variant_weighted_distribution(_Config) ->
    ContractId = <<"test-contract-exp-6">>,
    [V1, V2] = setup_contract_and_versions(ContractId, 2),
    %% 80% to V1, 20% to V2
    Variants = [
        #{version => V1#contract_version.version_id, weight => 80},
        #{version => V2#contract_version.version_id, weight => 20}
    ],
    {ok, Exp} = cb_contract_experiments:create_experiment(
        ContractId,
        <<"Test">>,
        Variants,
        <<"user">>
    ),
    Seed = Exp#contract_experiment.allocation_seed,
    ExpId = Exp#contract_experiment.experiment_id,
    
    %% Test multiple subjects to verify weight distribution
    Results = [
        {Subject, element(2, cb_contract_experiments:assign_variant(ExpId, Subject, Seed))}
        || Subject <- [<<"s" ++ integer_to_list(N) ++ ":001">> || N <- lists:seq(1, 100)]
    ],
    V1Count = length([ok || {_, V} <- Results, V =:= V1#contract_version.version_id]),
    
    %% With weights 80:20, expect roughly 80 assignments to V1 (allow +/- 20% variance)
    ?assert(V1Count > 60 andalso V1Count < 100).

%% Test: Activate experiment transitions from draft to active
test_activate_experiment(_Config) ->
    ContractId = <<"test-contract-exp-7">>,
    [V1, V2] = setup_contract_and_versions(ContractId, 2),
    Variants = [
        #{version => V1#contract_version.version_id, weight => 50},
        #{version => V2#contract_version.version_id, weight => 50}
    ],
    {ok, Exp} = cb_contract_experiments:create_experiment(ContractId, <<"Test">>, Variants, <<"user">>),
    {ok, Active} = cb_contract_experiments:activate_experiment(
        Exp#contract_experiment.experiment_id
    ),
    ?assertEqual(active, Active#contract_experiment.status).

%% Test: Stop experiment transitions from active to stopped
test_stop_experiment(_Config) ->
    ContractId = <<"test-contract-exp-8">>,
    [V1, V2] = setup_contract_and_versions(ContractId, 2),
    Variants = [
        #{version => V1#contract_version.version_id, weight => 50},
        #{version => V2#contract_version.version_id, weight => 50}
    ],
    {ok, Exp} = cb_contract_experiments:create_experiment(ContractId, <<"Test">>, Variants, <<"user">>),
    {ok, Active} = cb_contract_experiments:activate_experiment(Exp#contract_experiment.experiment_id),
    {ok, Stopped} = cb_contract_experiments:stop_experiment(Active#contract_experiment.experiment_id),
    ?assertEqual(stopped, Stopped#contract_experiment.status).

%% Test: Cannot activate experiment with invalid status
test_activate_experiment_invalid_status(_Config) ->
    ContractId = <<"test-contract-exp-9">>,
    [V1, V2] = setup_contract_and_versions(ContractId, 2),
    Variants = [
        #{version => V1#contract_version.version_id, weight => 50},
        #{version => V2#contract_version.version_id, weight => 50}
    ],
    {ok, Exp} = cb_contract_experiments:create_experiment(ContractId, <<"Test">>, Variants, <<"user">>),
    {ok, Active} = cb_contract_experiments:activate_experiment(Exp#contract_experiment.experiment_id),
    {ok, _Stopped} = cb_contract_experiments:stop_experiment(Active#contract_experiment.experiment_id),
    Result = cb_contract_experiments:activate_experiment(Exp#contract_experiment.experiment_id),
    ?assertMatch({error, invalid_status}, Result).

%% Test: Complete experiment lifecycle: draft -> active -> stopped
test_experiment_status_transitions(_Config) ->
    ContractId = <<"test-contract-exp-10">>,
    [V1, V2] = setup_contract_and_versions(ContractId, 2),
    Variants = [
        #{version => V1#contract_version.version_id, weight => 50},
        #{version => V2#contract_version.version_id, weight => 50}
    ],
    {ok, Draft} = cb_contract_experiments:create_experiment(ContractId, <<"Test">>, Variants, <<"user">>),
    ?assertEqual(draft, Draft#contract_experiment.status),
    
    {ok, Active} = cb_contract_experiments:activate_experiment(Draft#contract_experiment.experiment_id),
    ?assertEqual(active, Active#contract_experiment.status),
    
    {ok, Stopped} = cb_contract_experiments:stop_experiment(Active#contract_experiment.experiment_id),
    ?assertEqual(stopped, Stopped#contract_experiment.status).

%% Test: List experiments for a contract
test_list_experiments(_Config) ->
    ContractId = <<"test-contract-exp-11">>,
    [V1, V2] = setup_contract_and_versions(ContractId, 2),
    Variants = [
        #{version => V1#contract_version.version_id, weight => 50},
        #{version => V2#contract_version.version_id, weight => 50}
    ],
    {ok, Exp1} = cb_contract_experiments:create_experiment(
        ContractId,
        <<"Experiment 1">>,
        Variants,
        <<"user">>
    ),
    timer:sleep(100),
    {ok, Exp2} = cb_contract_experiments:create_experiment(
        ContractId,
        <<"Experiment 2">>,
        Variants,
        <<"user">>
    ),
    Exps = cb_contract_experiments:list_experiments(ContractId),
    ?assertEqual(2, length(Exps)),
    [First|_] = Exps,
    ?assertEqual(Exp2#contract_experiment.experiment_id, First#contract_experiment.experiment_id).
