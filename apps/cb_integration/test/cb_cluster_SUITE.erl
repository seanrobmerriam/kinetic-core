%% @doc CT suite for cb_cluster (TASK-066).
-module(cb_cluster_SUITE).
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
    test_register_node/1,
    test_deregister_node/1,
    test_list_nodes/1,
    test_get_node/1,
    test_update_heartbeat/1,
    test_set_role_and_status/1,
    test_active_nodes_filter/1,
    test_cluster_transaction_no_nodes/1,
    test_cluster_transaction_with_nodes/1,
    test_deregister_not_found/1
]).

all() ->
    [test_register_node,
     test_deregister_node,
     test_list_nodes,
     test_get_node,
     test_update_heartbeat,
     test_set_role_and_status,
     test_active_nodes_filter,
     test_cluster_transaction_no_nodes,
     test_cluster_transaction_with_nodes,
     test_deregister_not_found].

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
    {atomic, ok} = mnesia:clear_table(cluster_node),
    Config.

end_per_testcase(_TestCase, _Config) -> ok.

%%--------------------------------------------------------------------
%% Test cases
%%--------------------------------------------------------------------

test_register_node(_Config) ->
    {ok, NodeId} = cb_cluster:register_node(sample_node()),
    true = is_binary(NodeId),
    {ok, Node} = cb_cluster:get_node(NodeId),
    <<"node@localhost">> = atom_to_binary(Node#cluster_node.erlang_node, utf8),
    active = Node#cluster_node.status.

test_deregister_node(_Config) ->
    {ok, NodeId} = cb_cluster:register_node(sample_node()),
    ok = cb_cluster:deregister_node(NodeId),
    {error, not_found} = cb_cluster:get_node(NodeId).

test_list_nodes(_Config) ->
    {ok, _} = cb_cluster:register_node(sample_node()),
    {ok, _} = cb_cluster:register_node(sample_node()),
    Nodes = cb_cluster:list_nodes(),
    true = length(Nodes) >= 2.

test_get_node(_Config) ->
    {ok, NodeId} = cb_cluster:register_node(sample_node()),
    {ok, #cluster_node{node_id = NodeId}} = cb_cluster:get_node(NodeId),
    {error, not_found} = cb_cluster:get_node(<<"nonexistent">>).

test_update_heartbeat(_Config) ->
    {ok, NodeId} = cb_cluster:register_node(sample_node()),
    {ok, N1} = cb_cluster:get_node(NodeId),
    timer:sleep(5),
    ok = cb_cluster:update_heartbeat(NodeId),
    {ok, N2} = cb_cluster:get_node(NodeId),
    true = N2#cluster_node.last_heartbeat_at >= N1#cluster_node.last_heartbeat_at.

test_set_role_and_status(_Config) ->
    {ok, NodeId} = cb_cluster:register_node(sample_node()),
    ok = cb_cluster:set_role(NodeId, primary),
    ok = cb_cluster:set_status(NodeId, inactive),
    {ok, Node} = cb_cluster:get_node(NodeId),
    primary  = Node#cluster_node.role,
    inactive = Node#cluster_node.status.

test_active_nodes_filter(_Config) ->
    {ok, NodeId1} = cb_cluster:register_node(sample_node()),
    {ok, NodeId2} = cb_cluster:register_node(sample_node()),
    ok = cb_cluster:set_status(NodeId2, inactive),
    Active = cb_cluster:active_nodes(),
    Ids = [N#cluster_node.node_id || N <- Active],
    true  = lists:member(NodeId1, Ids),
    false = lists:member(NodeId2, Ids).

test_cluster_transaction_no_nodes(_Config) ->
    {error, no_active_nodes} = cb_cluster:cluster_transaction(fun() -> ok end).

test_cluster_transaction_with_nodes(_Config) ->
    {ok, _} = cb_cluster:register_node(sample_node()),
    {ok, ok} = cb_cluster:cluster_transaction(fun() -> ok end).

test_deregister_not_found(_Config) ->
    {error, not_found} = cb_cluster:deregister_node(<<"does-not-exist">>).

%%--------------------------------------------------------------------
%% Helpers
%%--------------------------------------------------------------------

sample_node() ->
    #{erlang_node => 'node@localhost',
      host        => <<"localhost">>,
      port        => 4369,
      role        => replica}.
