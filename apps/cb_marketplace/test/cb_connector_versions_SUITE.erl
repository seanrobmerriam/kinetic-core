%% @doc CT tests for cb_connector_versions — TASK-057 versioning and rollback.
-module(cb_connector_versions_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    snapshot_connector_ok/1,
    snapshot_nonexistent_connector/1,
    list_versions_empty/1,
    list_versions_sorted_newest_first/1,
    get_version_not_found/1,
    rollback_restores_config/1,
    rollback_wrong_connector_rejected/1
]).

all() ->
    [
        snapshot_connector_ok,
        snapshot_nonexistent_connector,
        list_versions_empty,
        list_versions_sorted_newest_first,
        get_version_not_found,
        rollback_restores_config,
        rollback_wrong_connector_rejected
    ].

init_per_suite(Config) ->
    mnesia:start(),
    cb_schema:create_tables(),
    Config.

end_per_suite(_Config) ->
    mnesia:stop(),
    mnesia:delete_schema([node()]),
    ok.

init_per_testcase(_TestCase, Config) ->
    mnesia:clear_table(connector_definition),
    mnesia:clear_table(connector_version),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

register_test_connector() ->
    {ok, C} = cb_connectors:register(#{
        name => <<"Version Test">>, type => aws, module => cb_connector_aws,
        version => <<"1.0.0">>,
        capabilities => [<<"s3">>],
        config_schema => #{region => <<"us-east-1">>},
        description => <<"Test">>
    }),
    C.

snapshot_connector_ok(_Config) ->
    C = register_test_connector(),
    ConnId = C#connector_definition.connector_id,
    {ok, V} = cb_connector_versions:snapshot_version(ConnId),
    ?assertEqual(ConnId, V#connector_version.connector_id),
    ?assertEqual(<<"1.0.0">>, V#connector_version.version),
    ?assert(V#connector_version.is_active).

snapshot_nonexistent_connector(_Config) ->
    ?assertEqual({error, not_found}, cb_connector_versions:snapshot_version(<<"bad-id">>)).

list_versions_empty(_Config) ->
    C = register_test_connector(),
    ?assertEqual([], cb_connector_versions:list_versions(C#connector_definition.connector_id)).

list_versions_sorted_newest_first(_Config) ->
    C      = register_test_connector(),
    ConnId = C#connector_definition.connector_id,
    {ok, _V1} = cb_connector_versions:snapshot_version(ConnId),
    timer:sleep(5),
    {ok, V2} = cb_connector_versions:snapshot_version(ConnId),
    Versions = cb_connector_versions:list_versions(ConnId),
    ?assertEqual(2, length(Versions)),
    [First | _] = Versions,
    ?assertEqual(V2#connector_version.version_id, First#connector_version.version_id).

get_version_not_found(_Config) ->
    ?assertEqual({error, not_found}, cb_connector_versions:get_version(<<"bad-vid">>)).

rollback_restores_config(_Config) ->
    C      = register_test_connector(),
    ConnId = C#connector_definition.connector_id,
    {ok, V1} = cb_connector_versions:snapshot_version(ConnId),
    %% Update connector config
    {ok, _} = cb_connectors:update(ConnId, #{config_schema => #{region => <<"eu-west-1">>}}),
    %% Rollback to V1
    {ok, Restored} = cb_connector_versions:rollback(ConnId, V1#connector_version.version_id),
    ?assertEqual(#{region => <<"us-east-1">>}, Restored#connector_definition.config_schema).

rollback_wrong_connector_rejected(_Config) ->
    C1 = register_test_connector(),
    C2 = register_test_connector(),
    {ok, V2} = cb_connector_versions:snapshot_version(C2#connector_definition.connector_id),
    ?assertEqual({error, version_connector_mismatch},
                 cb_connector_versions:rollback(
                     C1#connector_definition.connector_id,
                     V2#connector_version.version_id)).
