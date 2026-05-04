%% @doc HTTP handler for cluster node management (TASK-066).
%%
%% Routes (see cb_router.erl):
%%   GET    /api/v1/cluster/nodes          → list nodes
%%   POST   /api/v1/cluster/nodes          → register node
%%   GET    /api/v1/cluster/nodes/:node_id → get node
%%   DELETE /api/v1/cluster/nodes/:node_id → deregister node
%%   POST   /api/v1/cluster/nodes/:node_id/heartbeat → update heartbeat
%%   GET    /api/v1/cluster/nodes/active   → list active nodes
-module(cb_cluster_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-define(JSON, #{<<"content-type">> => <<"application/json">>}).

init(Req, State) ->
    Method  = cowboy_req:method(Req),
    NodeId  = cowboy_req:binding(node_id, Req),
    SubPath = cowboy_req:binding(action, Req),
    handle(Method, NodeId, SubPath, Req, State).

%% POST /api/v1/cluster/nodes/:node_id/heartbeat
handle(<<"POST">>, NodeId, <<"heartbeat">>, Req, State) when NodeId =/= undefined ->
    case cb_cluster:update_heartbeat(NodeId) of
        ok              -> reply(200, #{status => <<"ok">>}, Req, State);
        {error, not_found} -> error_reply(404, <<"not_found">>, <<"Node not found">>, Req, State)
    end;

%% GET /api/v1/cluster/nodes/active
handle(<<"GET">>, <<"active">>, undefined, Req, State) ->
    Nodes = cb_cluster:active_nodes(),
    reply(200, #{nodes => [node_to_map(N) || N <- Nodes]}, Req, State);

%% GET /api/v1/cluster/nodes/:node_id
handle(<<"GET">>, NodeId, undefined, Req, State) when NodeId =/= undefined ->
    case cb_cluster:get_node(NodeId) of
        {ok, Node}         -> reply(200, node_to_map(Node), Req, State);
        {error, not_found} -> error_reply(404, <<"not_found">>, <<"Node not found">>, Req, State)
    end;

%% DELETE /api/v1/cluster/nodes/:node_id
handle(<<"DELETE">>, NodeId, undefined, Req, State) when NodeId =/= undefined ->
    case cb_cluster:deregister_node(NodeId) of
        ok                 -> reply(204, #{}, Req, State);
        {error, not_found} -> error_reply(404, <<"not_found">>, <<"Node not found">>, Req, State)
    end;

%% GET /api/v1/cluster/nodes
handle(<<"GET">>, undefined, undefined, Req, State) ->
    Nodes = cb_cluster:list_nodes(),
    reply(200, #{nodes => [node_to_map(N) || N <- Nodes]}, Req, State);

%% POST /api/v1/cluster/nodes
handle(<<"POST">>, undefined, undefined, Req0, State) ->
    {ok, Body, Req} = cowboy_req:read_body(Req0),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, Params, _} ->
            Required = [erlang_node, host, port, role],
            case validate_required(Params, Required) of
                ok ->
                    ENode = binary_to_atom(maps:get(erlang_node, Params), utf8),
                    Host  = maps:get(host, Params),
                    Port  = maps:get(port, Params),
                    Role  = binary_to_atom(maps:get(role, Params), utf8),
                    case cb_cluster:register_node(#{
                            erlang_node => ENode,
                            host        => Host,
                            port        => Port,
                            role        => Role}) of
                        {ok, NodeId} ->
                            reply(201, #{node_id => NodeId}, Req, State);
                        {error, Reason} ->
                            error_reply(422, Reason, <<"Registration failed">>, Req, State)
                    end;
                {missing, Field} ->
                    Msg = iolist_to_binary([<<"Missing field: ">>, atom_to_binary(Field, utf8)]),
                    error_reply(400, <<"missing_field">>, Msg, Req, State)
            end;
        {error, _} ->
            error_reply(400, <<"invalid_json">>, <<"Invalid JSON body">>, Req, State)
    end;

handle(_, _, _, Req, State) ->
    error_reply(405, <<"method_not_allowed">>, <<"Method not allowed">>, Req, State).

%%--------------------------------------------------------------------
%% Internal
%%--------------------------------------------------------------------

node_to_map(#cluster_node{
        node_id           = Id,
        erlang_node       = ENode,
        host              = Host,
        port              = Port,
        role              = Role,
        status            = Status,
        registered_at     = RegAt,
        last_heartbeat_at = HbAt}) ->
    #{node_id           => Id,
      erlang_node       => atom_to_binary(ENode, utf8),
      host              => Host,
      port              => Port,
      role              => atom_to_binary(Role, utf8),
      status            => atom_to_binary(Status, utf8),
      registered_at     => RegAt,
      last_heartbeat_at => HbAt}.

validate_required(Params, Fields) ->
    case [F || F <- Fields, not maps:is_key(F, Params)] of
        []        -> ok;
        [First|_] -> {missing, First}
    end.

reply(Status, Body, Req, State) ->
    Resp = cowboy_req:reply(Status, ?JSON, jsone:encode(Body), Req),
    {ok, Resp, State}.

error_reply(Status, Reason, Message, Req, State) ->
    ReasonBin = if is_atom(Reason)   -> atom_to_binary(Reason, utf8);
                   is_binary(Reason) -> Reason;
                   true              -> iolist_to_binary(io_lib:format("~p", [Reason]))
                end,
    reply(Status, #{error => ReasonBin, message => Message}, Req, State).
