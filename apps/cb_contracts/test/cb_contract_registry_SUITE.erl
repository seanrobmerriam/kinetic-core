%% @doc Common Test suite for cb_contract_registry module
%%
%% Tests contract CRUD operations, versioning, migrations, and idempotency.
-module(cb_contract_registry_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include("../include/cb_contracts.hrl").

-compile(export_all).

suite() ->
    [{timetrap, {seconds, 30}}].

all() ->
    [
        test_create_contract_basic,
        test_create_contract_idempotent,
        test_create_contract_missing_fields,
        test_deploy_version_basic,
        test_deploy_version_invalid_schema,
        test_deploy_version_too_large,
        test_activate_version_basic,
        test_activate_version_not_found,
        test_activate_version_deactivates_others,
        test_create_migration_basic,
        test_create_migration_incompatible_versions,
        test_list_versions_sorted,
        test_list_migrations_sorted
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

%% Test: Create contract with basic fields
test_create_contract_basic(_Config) ->
    ContractId = <<"test-contract-1">>,
    Attrs = #{
        contract_id => ContractId,
        name => <<"My Contract">>,
        domain => <<"payments">>,
        owner_role => <<"admin">>
    },
    {ok, Contract} = cb_contract_registry:create_contract(Attrs),
    ?assertEqual(ContractId, Contract#contract_definition.contract_id),
    ?assertEqual(<<"My Contract">>, Contract#contract_definition.name),
    ?assertEqual(<<"payments">>, Contract#contract_definition.domain),
    ?assertEqual(<<"admin">>, Contract#contract_definition.owner_role),
    ?assertEqual(draft, Contract#contract_definition.status).

%% Test: Create contract twice with same ID (idempotent)
test_create_contract_idempotent(_Config) ->
    ContractId = <<"test-contract-2">>,
    Attrs = #{
        contract_id => ContractId,
        name => <<"My Contract">>,
        domain => <<"payments">>,
        owner_role => <<"admin">>
    },
    {ok, Contract1} = cb_contract_registry:create_contract(Attrs),
    {ok, Contract2} = cb_contract_registry:create_contract(Attrs),
    ?assertEqual(Contract1#contract_definition.contract_id,
                 Contract2#contract_definition.contract_id).

%% Test: Create contract without required fields
test_create_contract_missing_fields(_Config) ->
    Attrs = #{name => <<"My Contract">>},
    Result = cb_contract_registry:create_contract(Attrs),
    ?assertMatch({error, _}, Result).

%% Test: Deploy a version with valid contract DSL
test_deploy_version_basic(_Config) ->
    ContractId = <<"test-contract-3">>,
    cb_contract_registry:create_contract(#{
        contract_id => ContractId,
        name => <<"Test">>,
        domain => <<"payments">>,
        owner_role => <<"admin">>
    }),
    Payload = #{
        rules => [
            #{'when' => #{account_status => <<"active">>},
              'then' => #{action => set, decision => approve}}
        ]
    },
    {ok, Version} = cb_contract_registry:deploy_version(ContractId, <<"1.0">>, Payload, <<"test_user">>),
    ?assertEqual(ContractId, Version#contract_version.contract_id),
    ?assertEqual(<<"1.0">>, Version#contract_version.version),
    ?assertEqual(draft, Version#contract_version.status),
    ?assertNotEqual(undefined, Version#contract_version.checksum).

%% Test: Deploy version with invalid DSL (fails validation)
test_deploy_version_invalid_schema(_Config) ->
    ContractId = <<"test-contract-4">>,
    cb_contract_registry:create_contract(#{
        contract_id => ContractId,
        name => <<"Test">>,
        domain => <<"payments">>,
        owner_role => <<"admin">>
    }),
    Payload = #{
        rules => [
            #{'when' => #{bad_operator => {foo, bar}}}
        ]
    },
    Result = cb_contract_registry:deploy_version(ContractId, <<"1.0">>, Payload, <<"test_user">>),
    ?assertMatch({error, _}, Result).

%% Test: Deploy version exceeding size limit
test_deploy_version_too_large(_Config) ->
    ContractId = <<"test-contract-5">>,
    cb_contract_registry:create_contract(#{
        contract_id => ContractId,
        name => <<"Test">>,
        domain => <<"payments">>,
        owner_role => <<"admin">>
    }),
    %% Generate a payload larger than 128 KB
    LargePayload = #{
        rules => [
            #{'when' => #{field => binary:copy(<<"x">>, 150000)},
              'then' => #{action => set, decision => approve}}
        ]
    },
    Result = cb_contract_registry:deploy_version(ContractId, <<"1.0">>, LargePayload, <<"test_user">>),
    ?assertMatch({error, _}, Result).

%% Test: Activate a version
test_activate_version_basic(_Config) ->
    ContractId = <<"test-contract-6">>,
    cb_contract_registry:create_contract(#{
        contract_id => ContractId,
        name => <<"Test">>,
        domain => <<"payments">>,
        owner_role => <<"admin">>
    }),
    Payload = #{rules => [#{'when' => #{}, 'then' => #{action => set, decision => approve}}]},
    {ok, Version1} = cb_contract_registry:deploy_version(ContractId, <<"1.0">>, Payload, <<"user">>),
    {ok, Contract} = cb_contract_registry:activate_version(ContractId, Version1#contract_version.version_id),
    ?assertEqual(Version1#contract_version.version_id, Contract#contract_definition.active_version).

%% Test: Activate version that doesn't exist
test_activate_version_not_found(_Config) ->
    Result = cb_contract_registry:activate_version(<<"nonexistent">>, <<"v1">>),
    ?assertMatch({error, contract_version_not_found}, Result).

%% Test: Activating new version deactivates old one
test_activate_version_deactivates_others(_Config) ->
    ContractId = <<"test-contract-7">>,
    cb_contract_registry:create_contract(#{
        contract_id => ContractId,
        name => <<"Test">>,
        domain => <<"payments">>,
        owner_role => <<"admin">>
    }),
    Payload1 = #{rules => [#{'when' => #{}, 'then' => #{action => set, decision => approve}}]},
    Payload2 = #{rules => [#{'when' => #{}, 'then' => #{action => set, decision => reject}}]},
    {ok, Version1} = cb_contract_registry:deploy_version(ContractId, <<"1.0">>, Payload1, <<"user">>),
    {ok, Version2} = cb_contract_registry:deploy_version(ContractId, <<"2.0">>, Payload2, <<"user">>),
    {ok, _} = cb_contract_registry:activate_version(ContractId, Version1#contract_version.version_id),
    {ok, Contract} = cb_contract_registry:activate_version(ContractId, Version2#contract_version.version_id),
    ?assertEqual(Version2#contract_version.version_id, Contract#contract_definition.active_version).

%% Test: Create migration between versions
test_create_migration_basic(_Config) ->
    ContractId = <<"test-contract-8">>,
    cb_contract_registry:create_contract(#{
        contract_id => ContractId,
        name => <<"Test">>,
        domain => <<"payments">>,
        owner_role => <<"admin">>
    }),
    Payload1 = #{rules => [#{'when' => #{}, 'then' => #{action => set, decision => approve}}]},
    Payload2 = #{rules => [#{'when' => #{}, 'then' => #{action => set, decision => reject}}]},
    {ok, V1} = cb_contract_registry:deploy_version(ContractId, <<"1.0">>, Payload1, <<"user">>),
    {ok, V2} = cb_contract_registry:deploy_version(ContractId, <<"2.0">>, Payload2, <<"user">>),
    {ok, Migration} = cb_contract_registry:create_migration(
        ContractId,
        V1#contract_version.version_id,
        V2#contract_version.version_id,
        compatible,
        <<"No breaking changes">>
    ),
    ?assertEqual(ContractId, Migration#contract_migration.contract_id),
    ?assertEqual(V1#contract_version.version_id, Migration#contract_migration.from_version),
    ?assertEqual(V2#contract_version.version_id, Migration#contract_migration.to_version),
    ?assertEqual(compatible, Migration#contract_migration.strategy).

%% Test: Create migration with incompatible versions (error)
test_create_migration_incompatible_versions(_Config) ->
    Result = cb_contract_registry:create_migration(
        <<"nonexistent">>,
        <<"v1">>,
        <<"v2">>,
        compatible,
        <<"test">>
    ),
    ?assertMatch({error, _}, Result).

%% Test: List versions sorted by creation time (descending)
test_list_versions_sorted(_Config) ->
    ContractId = <<"test-contract-9">>,
    cb_contract_registry:create_contract(#{
        contract_id => ContractId,
        name => <<"Test">>,
        domain => <<"payments">>,
        owner_role => <<"admin">>
    }),
    Payload = #{rules => [#{'when' => #{}, 'then' => #{action => set, decision => approve}}]},
    {ok, _V1} = cb_contract_registry:deploy_version(ContractId, <<"1.0">>, Payload, <<"user">>),
    timer:sleep(100),
    {ok, V2} = cb_contract_registry:deploy_version(ContractId, <<"2.0">>, Payload, <<"user">>),
    Versions = cb_contract_registry:list_versions(ContractId),
    ?assertEqual(2, length(Versions)),
    [First|_] = Versions,
    ?assertEqual(V2#contract_version.version_id, First#contract_version.version_id).

%% Test: List migrations sorted by creation time (descending)
test_list_migrations_sorted(_Config) ->
    ContractId = <<"test-contract-10">>,
    cb_contract_registry:create_contract(#{
        contract_id => ContractId,
        name => <<"Test">>,
        domain => <<"payments">>,
        owner_role => <<"admin">>
    }),
    Payload = #{rules => [#{'when' => #{}, 'then' => #{action => set, decision => approve}}]},
    {ok, V1} = cb_contract_registry:deploy_version(ContractId, <<"1.0">>, Payload, <<"user">>),
    {ok, V2} = cb_contract_registry:deploy_version(ContractId, <<"2.0">>, Payload, <<"user">>),
    {ok, V3} = cb_contract_registry:deploy_version(ContractId, <<"3.0">>, Payload, <<"user">>),
    {ok, _M1} = cb_contract_registry:create_migration(ContractId, V1#contract_version.version_id, 
                                                       V2#contract_version.version_id, compatible, <<"test">>),
    timer:sleep(100),
    {ok, M2} = cb_contract_registry:create_migration(ContractId, V2#contract_version.version_id, 
                                                       V3#contract_version.version_id, compatible, <<"test">>),
    Migrations = cb_contract_registry:list_migrations(ContractId),
    ?assertEqual(2, length(Migrations)),
    [First|_] = Migrations,
    ?assertEqual(M2#contract_migration.migration_id, First#contract_migration.migration_id).
