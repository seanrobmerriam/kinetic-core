%% @doc Failover and Recovery Orchestration (TASK-069).
%%
%% Manages recovery checkpoints for stateful resources.  A checkpoint captures
%% a serialised state snapshot at a point in time.  During a failover event
%% the orchestrator initiates recovery from the latest valid checkpoint,
%% applies the snapshot, and marks the checkpoint completed.
%%
%% Status flow: pending → active → completed | aborted
-module(cb_recovery).
-compile({parse_transform, ms_transform}).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    create_checkpoint/1,
    get_checkpoint/1,
    list_checkpoints/2,
    latest_checkpoint/2,
    initiate_recovery/1,
    complete_recovery/1,
    abort_recovery/1,
    validate_recovery/1
]).

-spec create_checkpoint(map()) -> {ok, uuid()} | {error, term()}.
create_checkpoint(#{resource_type := RT, resource_id := RId, state_snapshot := Snap}) ->
    CheckpointId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
    Now = erlang:system_time(millisecond),
    Record = #recovery_checkpoint{
        checkpoint_id  = CheckpointId,
        resource_type  = RT,
        resource_id    = RId,
        state_snapshot = Snap,
        status         = pending,
        created_at     = Now,
        completed_at   = undefined
    },
    case mnesia:transaction(fun() -> mnesia:write(Record) end) of
        {atomic, ok}     -> {ok, CheckpointId};
        {aborted, Reason} -> {error, Reason}
    end.

-spec get_checkpoint(uuid()) -> {ok, #recovery_checkpoint{}} | {error, not_found}.
get_checkpoint(CheckpointId) ->
    case mnesia:dirty_read(recovery_checkpoint, CheckpointId) of
        [C] -> {ok, C};
        []  -> {error, not_found}
    end.

-spec list_checkpoints(binary(), uuid()) -> [#recovery_checkpoint{}].
list_checkpoints(ResourceType, ResourceId) ->
    MS = ets:fun2ms(fun(#recovery_checkpoint{resource_type = RT,
                                              resource_id   = RId} = C)
                        when RT =:= ResourceType, RId =:= ResourceId -> C end),
    {atomic, Checkpoints} = mnesia:transaction(fun() ->
        mnesia:select(recovery_checkpoint, MS)
    end),
    lists:sort(fun(A, B) ->
        A#recovery_checkpoint.created_at >= B#recovery_checkpoint.created_at
    end, Checkpoints).

-spec latest_checkpoint(binary(), uuid()) ->
    {ok, #recovery_checkpoint{}} | {error, not_found}.
latest_checkpoint(ResourceType, ResourceId) ->
    case list_checkpoints(ResourceType, ResourceId) of
        []    -> {error, not_found};
        [C|_] -> {ok, C}
    end.

%% @doc Transition a pending checkpoint to active, marking recovery as started.
-spec initiate_recovery(uuid()) -> ok | {error, not_found | invalid_status}.
initiate_recovery(CheckpointId) ->
    transition(CheckpointId, pending, active).

%% @doc Transition an active checkpoint to completed, recording finish time.
-spec complete_recovery(uuid()) -> ok | {error, not_found | invalid_status}.
complete_recovery(CheckpointId) ->
    Now = erlang:system_time(millisecond),
    case mnesia:transaction(fun() ->
        case mnesia:read(recovery_checkpoint, CheckpointId) of
            []  -> {error, not_found};
            [C] when C#recovery_checkpoint.status =/= active -> {error, invalid_status};
            [C] ->
                mnesia:write(C#recovery_checkpoint{
                    status       = completed,
                    completed_at = Now
                }),
                ok
        end
    end) of
        {atomic, Result}  -> Result;
        {aborted, Reason} -> {error, Reason}
    end.

%% @doc Abort a pending or active recovery.
-spec abort_recovery(uuid()) -> ok | {error, not_found | invalid_status}.
abort_recovery(CheckpointId) ->
    case mnesia:transaction(fun() ->
        case mnesia:read(recovery_checkpoint, CheckpointId) of
            []  -> {error, not_found};
            [C] when C#recovery_checkpoint.status =:= completed -> {error, invalid_status};
            [C] ->
                mnesia:write(C#recovery_checkpoint{status = aborted}),
                ok
        end
    end) of
        {atomic, Result}  -> Result;
        {aborted, Reason} -> {error, Reason}
    end.

%% @doc Validate that a completed recovery checkpoint has a non-empty snapshot
%% and is in the completed status.  Returns ok or {error, Reason}.
-spec validate_recovery(uuid()) ->
    ok | {error, not_found | not_completed | empty_snapshot}.
validate_recovery(CheckpointId) ->
    case get_checkpoint(CheckpointId) of
        {error, not_found} ->
            {error, not_found};
        {ok, C} when C#recovery_checkpoint.status =/= completed ->
            {error, not_completed};
        {ok, C} when C#recovery_checkpoint.state_snapshot =:= <<>> ->
            {error, empty_snapshot};
        {ok, _} ->
            ok
    end.

%%--------------------------------------------------------------------
%% Internal
%%--------------------------------------------------------------------

transition(CheckpointId, FromStatus, ToStatus) ->
    case mnesia:transaction(fun() ->
        case mnesia:read(recovery_checkpoint, CheckpointId) of
            []  -> {error, not_found};
            [C] when C#recovery_checkpoint.status =/= FromStatus -> {error, invalid_status};
            [C] ->
                mnesia:write(C#recovery_checkpoint{status = ToStatus}),
                ok
        end
    end) of
        {atomic, Result}  -> Result;
        {aborted, Reason} -> {error, Reason}
    end.
