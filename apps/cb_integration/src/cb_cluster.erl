%% @doc Distributed Transaction Processing Cluster Management (TASK-066).
%%
%% Manages the set of Erlang nodes that form the processing cluster.
%% Provides cluster-aware transaction wrapping so callers can execute
%% Mnesia transactions with a pre-flight cluster health check.
%%
%% Node lifecycle: register → active (heartbeat) → inactive / unreachable.
-module(cb_cluster).
-compile({parse_transform, ms_transform}).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    register_node/1,
    deregister_node/1,
    list_nodes/0,
    get_node/1,
    update_heartbeat/1,
    set_role/2,
    set_status/2,
    active_nodes/0,
    cluster_transaction/1
]).

-spec register_node(map()) -> {ok, uuid()} | {error, term()}.
register_node(#{erlang_node := ENode, host := Host, port := Port, role := Role}) ->
    NodeId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
    Now    = erlang:system_time(millisecond),
    Record = #cluster_node{
        node_id           = NodeId,
        erlang_node       = ENode,
        host              = Host,
        port              = Port,
        role              = Role,
        status            = active,
        registered_at     = Now,
        last_heartbeat_at = Now
    },
    case mnesia:transaction(fun() -> mnesia:write(Record) end) of
        {atomic, ok}     -> {ok, NodeId};
        {aborted, Reason} -> {error, Reason}
    end.

-spec deregister_node(uuid()) -> ok | {error, not_found}.
deregister_node(NodeId) ->
    case mnesia:transaction(fun() ->
        case mnesia:read(cluster_node, NodeId) of
            []  -> {error, not_found};
            [_] -> mnesia:delete({cluster_node, NodeId}), ok
        end
    end) of
        {atomic, Result}  -> Result;
        {aborted, Reason} -> {error, Reason}
    end.

-spec list_nodes() -> [#cluster_node{}].
list_nodes() ->
    {atomic, Nodes} = mnesia:transaction(fun() ->
        mnesia:match_object(#cluster_node{_ = '_'})
    end),
    Nodes.

-spec get_node(uuid()) -> {ok, #cluster_node{}} | {error, not_found}.
get_node(NodeId) ->
    case mnesia:dirty_read(cluster_node, NodeId) of
        [Node] -> {ok, Node};
        []     -> {error, not_found}
    end.

-spec update_heartbeat(uuid()) -> ok | {error, not_found}.
update_heartbeat(NodeId) ->
    Now = erlang:system_time(millisecond),
    case mnesia:transaction(fun() ->
        case mnesia:read(cluster_node, NodeId) of
            [] -> {error, not_found};
            [N] ->
                mnesia:write(N#cluster_node{
                    status            = active,
                    last_heartbeat_at = Now
                }),
                ok
        end
    end) of
        {atomic, Result}  -> Result;
        {aborted, Reason} -> {error, Reason}
    end.

-spec set_role(uuid(), cluster_node_role()) -> ok | {error, not_found}.
set_role(NodeId, Role) ->
    update_field(NodeId, fun(N) -> N#cluster_node{role = Role} end).

-spec set_status(uuid(), cluster_node_status()) -> ok | {error, not_found}.
set_status(NodeId, Status) ->
    update_field(NodeId, fun(N) -> N#cluster_node{status = Status} end).

-spec active_nodes() -> [#cluster_node{}].
active_nodes() ->
    MS = ets:fun2ms(fun(#cluster_node{status = active} = N) -> N end),
    {atomic, Nodes} = mnesia:transaction(fun() ->
        mnesia:select(cluster_node, MS)
    end),
    Nodes.

%% @doc Execute Fun inside an Mnesia transaction after verifying at least
%% one active cluster node is registered.  Returns {error, no_active_nodes}
%% when the cluster has no active members.
-spec cluster_transaction(fun(() -> term())) -> {ok, term()} | {error, term()}.
cluster_transaction(Fun) ->
    case active_nodes() of
        [] ->
            {error, no_active_nodes};
        [_|_] ->
            case mnesia:transaction(Fun) of
                {atomic, Result}  -> {ok, Result};
                {aborted, Reason} -> {error, Reason}
            end
    end.

%%--------------------------------------------------------------------
%% Internal
%%--------------------------------------------------------------------

update_field(NodeId, UpdateFun) ->
    case mnesia:transaction(fun() ->
        case mnesia:read(cluster_node, NodeId) of
            []  -> {error, not_found};
            [N] -> mnesia:write(UpdateFun(N)), ok
        end
    end) of
        {atomic, Result}  -> Result;
        {aborted, Reason} -> {error, Reason}
    end.
