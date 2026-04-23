%% @doc HTTP handler for failover and recovery checkpoint management (TASK-069).
%%
%% Routes (see cb_router.erl):
%%   POST /api/v1/recovery/checkpoints                             → create checkpoint
%%   GET  /api/v1/recovery/checkpoints/:checkpoint_id             → get checkpoint
%%   GET  /api/v1/recovery/:resource_type/:resource_id/checkpoints → list checkpoints
%%   GET  /api/v1/recovery/:resource_type/:resource_id/latest     → latest checkpoint
%%   POST /api/v1/recovery/checkpoints/:checkpoint_id/initiate    → initiate recovery
%%   POST /api/v1/recovery/checkpoints/:checkpoint_id/complete    → complete recovery
%%   POST /api/v1/recovery/checkpoints/:checkpoint_id/abort       → abort recovery
%%   GET  /api/v1/recovery/checkpoints/:checkpoint_id/validate    → validate recovery
-module(cb_recovery_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-define(JSON, #{<<"content-type">> => <<"application/json">>}).

init(Req, State) ->
    Method       = cowboy_req:method(Req),
    CheckpointId = cowboy_req:binding(checkpoint_id, Req),
    Action       = cowboy_req:binding(action, Req),
    ResourceType = cowboy_req:binding(resource_type, Req),
    ResourceId   = cowboy_req:binding(resource_id, Req),
    handle(Method, CheckpointId, Action, ResourceType, ResourceId, Req, State).

%% Sub-actions on a specific checkpoint
handle(<<"POST">>, CheckpointId, <<"initiate">>, _, _, Req, State) when CheckpointId =/= undefined ->
    case cb_recovery:initiate_recovery(CheckpointId) of
        ok                       -> reply(200, #{status => <<"active">>}, Req, State);
        {error, not_found}       -> error_reply(404, <<"not_found">>, <<"Checkpoint not found">>, Req, State);
        {error, invalid_status}  -> error_reply(409, <<"invalid_status">>, <<"Invalid checkpoint status">>, Req, State)
    end;

handle(<<"POST">>, CheckpointId, <<"complete">>, _, _, Req, State) when CheckpointId =/= undefined ->
    case cb_recovery:complete_recovery(CheckpointId) of
        ok                       -> reply(200, #{status => <<"completed">>}, Req, State);
        {error, not_found}       -> error_reply(404, <<"not_found">>, <<"Checkpoint not found">>, Req, State);
        {error, invalid_status}  -> error_reply(409, <<"invalid_status">>, <<"Invalid checkpoint status">>, Req, State)
    end;

handle(<<"POST">>, CheckpointId, <<"abort">>, _, _, Req, State) when CheckpointId =/= undefined ->
    case cb_recovery:abort_recovery(CheckpointId) of
        ok                       -> reply(200, #{status => <<"aborted">>}, Req, State);
        {error, not_found}       -> error_reply(404, <<"not_found">>, <<"Checkpoint not found">>, Req, State);
        {error, invalid_status}  -> error_reply(409, <<"invalid_status">>, <<"Already completed">>, Req, State)
    end;

handle(<<"GET">>, CheckpointId, <<"validate">>, _, _, Req, State) when CheckpointId =/= undefined ->
    case cb_recovery:validate_recovery(CheckpointId) of
        ok                        -> reply(200, #{valid => true}, Req, State);
        {error, not_found}        -> error_reply(404, <<"not_found">>, <<"Checkpoint not found">>, Req, State);
        {error, not_completed}    -> reply(200, #{valid => false, reason => <<"not_completed">>}, Req, State);
        {error, empty_snapshot}   -> reply(200, #{valid => false, reason => <<"empty_snapshot">>}, Req, State)
    end;

%% GET /api/v1/recovery/checkpoints/:checkpoint_id
handle(<<"GET">>, CheckpointId, undefined, _, _, Req, State) when CheckpointId =/= undefined ->
    case cb_recovery:get_checkpoint(CheckpointId) of
        {ok, C}            -> reply(200, checkpoint_to_map(C), Req, State);
        {error, not_found} -> error_reply(404, <<"not_found">>, <<"Checkpoint not found">>, Req, State)
    end;

%% GET /api/v1/recovery/:resource_type/:resource_id/checkpoints
handle(<<"GET">>, undefined, <<"checkpoints">>, RT, RId, Req, State)
        when RT =/= undefined, RId =/= undefined ->
    List = cb_recovery:list_checkpoints(RT, RId),
    reply(200, #{checkpoints => [checkpoint_to_map(C) || C <- List]}, Req, State);

%% GET /api/v1/recovery/:resource_type/:resource_id/latest
handle(<<"GET">>, undefined, <<"latest">>, RT, RId, Req, State)
        when RT =/= undefined, RId =/= undefined ->
    case cb_recovery:latest_checkpoint(RT, RId) of
        {ok, C}            -> reply(200, checkpoint_to_map(C), Req, State);
        {error, not_found} -> error_reply(404, <<"not_found">>, <<"No checkpoints found">>, Req, State)
    end;

%% POST /api/v1/recovery/checkpoints
handle(<<"POST">>, undefined, undefined, _, _, Req0, State) ->
    {ok, Body, Req} = cowboy_req:read_body(Req0),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, Params, _} ->
            Required = [resource_type, resource_id, state_snapshot],
            case validate_required(Params, Required) of
                ok ->
                    Input = #{
                        resource_type  => maps:get(resource_type, Params),
                        resource_id    => maps:get(resource_id, Params),
                        state_snapshot => maps:get(state_snapshot, Params)
                    },
                    case cb_recovery:create_checkpoint(Input) of
                        {ok, CId}       -> reply(201, #{checkpoint_id => CId}, Req, State);
                        {error, Reason} -> error_reply(422, Reason, <<"Checkpoint creation failed">>, Req, State)
                    end;
                {missing, Field} ->
                    Msg = iolist_to_binary([<<"Missing field: ">>, atom_to_binary(Field, utf8)]),
                    error_reply(400, <<"missing_field">>, Msg, Req, State)
            end;
        {error, _} ->
            error_reply(400, <<"invalid_json">>, <<"Invalid JSON body">>, Req, State)
    end;

handle(_, _, _, _, _, Req, State) ->
    error_reply(405, <<"method_not_allowed">>, <<"Method not allowed">>, Req, State).

%%--------------------------------------------------------------------
%% Internal
%%--------------------------------------------------------------------

checkpoint_to_map(#recovery_checkpoint{
        checkpoint_id  = Id,
        resource_type  = RT,
        resource_id    = RId,
        state_snapshot = Snap,
        status         = Status,
        created_at     = CreatedAt,
        completed_at   = CompletedAt}) ->
    #{checkpoint_id  => Id,
      resource_type  => RT,
      resource_id    => RId,
      state_snapshot => Snap,
      status         => atom_to_binary(Status, utf8),
      created_at     => CreatedAt,
      completed_at   => CompletedAt}.

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
