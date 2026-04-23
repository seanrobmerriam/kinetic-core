%% @doc KYC Workflow Builder and State Machine.
%%
%% Manages configurable KYC verification workflows bound to party records.
%% Each workflow is a sequence of typed steps that advance in order.
%%
%% == Workflow Lifecycle ==
%%
%% ```
%% pending -> in_progress -> completed
%%                        -> failed
%%                        -> abandoned
%% ```
%%
%% Steps within a workflow advance from:
%% ```
%% pending -> in_progress -> completed
%%                        -> failed
%%                        -> skipped
%% ```
%%
%% == Default Workflow ==
%%
%% The default workflow template creates five steps in order:
%% 1. document_collection
%% 2. identity_check
%% 3. sanctions_screening
%% 4. risk_assessment
%% 5. approval
%%
%% == Usage ==
%%
%% ```erlang
%% {ok, Workflow} = cb_kyc_workflow:create(PartyId, <<"Standard KYC">>),
%% {ok, Workflow2} = cb_kyc_workflow:start(Workflow#kyc_workflow.workflow_id),
%% {ok, Workflow3} = cb_kyc_workflow:advance_step(Workflow2#kyc_workflow.workflow_id, completed),
%% ```
-module(cb_kyc_workflow).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    create/2,
    get_workflow/1,
    list_all/0,
    list_for_party/1,
    start_workflow/1,
    advance_step/2,
    abandon_workflow/1,
    get_steps/1
]).

%% @doc Create a new KYC workflow for the given party.
%%
%% Persists the workflow and its default step sequence.
-spec create(uuid(), binary()) -> {ok, #kyc_workflow{}} | {error, not_found | atom()}.
create(PartyId, Name) ->
    case mnesia:dirty_read(party, PartyId) of
        [] ->
            {error, not_found};
        [_Party] ->
            WorkflowId = uuid:get_v4_urandom(),
            Now = erlang:system_time(millisecond),
            Steps = build_default_steps(WorkflowId, Now),
            StepIds = [S#kyc_step.step_id || S <- Steps],
            Workflow = #kyc_workflow{
                workflow_id     = WorkflowId,
                party_id        = PartyId,
                name            = Name,
                status          = pending,
                step_ids        = StepIds,
                current_step_id = undefined,
                completed_at    = undefined,
                created_at      = Now,
                updated_at      = Now
            },
            F = fun() ->
                lists:foreach(fun(Step) -> mnesia:write(kyc_step, Step, write) end, Steps),
                mnesia:write(kyc_workflow, Workflow, write),
                Workflow
            end,
            case mnesia:transaction(F) of
                {atomic, W} -> {ok, W};
                {aborted, Reason} -> {error, Reason}
            end
    end.

%% @doc Retrieve a workflow by its ID.
-spec get_workflow(uuid()) -> {ok, #kyc_workflow{}} | {error, not_found}.
get_workflow(WorkflowId) ->
    case mnesia:dirty_read(kyc_workflow, WorkflowId) of
        [] -> {error, not_found};
        [W] -> {ok, W}
    end.

%% @doc List all workflows for a party.
-spec list_for_party(uuid()) -> {ok, [#kyc_workflow{}]}.
list_for_party(PartyId) ->
    Workflows = mnesia:dirty_index_read(kyc_workflow, PartyId, party_id),
    {ok, Workflows}.

%% @doc List all KYC workflows across all parties.
-spec list_all() -> {ok, [#kyc_workflow{}]}.
list_all() ->
    Workflows = mnesia:dirty_match_object(kyc_workflow, mnesia:table_info(kyc_workflow, wild_pattern)),
    {ok, Workflows}.

%% @doc Start a pending workflow, activating its first step.
-spec start_workflow(uuid()) -> {ok, #kyc_workflow{}} | {error, atom()}.
start_workflow(WorkflowId) ->
    F = fun() ->
        case mnesia:read(kyc_workflow, WorkflowId, write) of
            [] ->
                {error, not_found};
            [W] when W#kyc_workflow.status =/= pending ->
                {error, invalid_workflow_status};
            [W] ->
                [FirstStepId | _] = W#kyc_workflow.step_ids,
                case mnesia:read(kyc_step, FirstStepId, write) of
                    [] -> {error, step_not_found};
                    [Step] ->
                        Now = erlang:system_time(millisecond),
                        Step2 = Step#kyc_step{status = in_progress},
                        mnesia:write(kyc_step, Step2, write),
                        W2 = W#kyc_workflow{
                            status          = in_progress,
                            current_step_id = FirstStepId,
                            updated_at      = Now
                        },
                        mnesia:write(kyc_workflow, W2, write),
                        W2
                end
        end
    end,
    case mnesia:transaction(F) of
        {atomic, {error, _} = Err} -> Err;
        {atomic, W}                -> {ok, W};
        {aborted, Reason}          -> {error, Reason}
    end.

%% @doc Advance the current step of a workflow to the given outcome.
%%
%% Outcome must be `completed', `failed', or `skipped'.
%% On completed/skipped, the next step is activated (or the workflow ends).
%% On failed, the workflow transitions to failed status.
-spec advance_step(uuid(), completed | failed | skipped | map()) ->
    {ok, #kyc_workflow{}} | {error, atom()}.
advance_step(WorkflowId, #{outcome := Outcome}) ->
    advance_step(WorkflowId, Outcome);
advance_step(WorkflowId, Outcome)
        when Outcome =:= completed; Outcome =:= failed; Outcome =:= skipped ->
    F = fun() ->
        case mnesia:read(kyc_workflow, WorkflowId, write) of
            [] ->
                {error, not_found};
            [W] when W#kyc_workflow.status =/= in_progress ->
                {error, invalid_workflow_status};
            [W] ->
                Now = erlang:system_time(millisecond),
                CurrentStepId = W#kyc_workflow.current_step_id,
                case mnesia:read(kyc_step, CurrentStepId, write) of
                    [] ->
                        {error, step_not_found};
                    [Step] ->
                        Step2 = Step#kyc_step{
                            status       = Outcome,
                            completed_at = Now
                        },
                        mnesia:write(kyc_step, Step2, write),
                        case Outcome of
                            failed ->
                                W2 = W#kyc_workflow{
                                    status     = failed,
                                    updated_at = Now
                                },
                                mnesia:write(kyc_workflow, W2, write),
                                W2;
                            _ ->
                                advance_to_next_step(W, Now)
                        end
                end
        end
    end,
    case mnesia:transaction(F) of
        {atomic, {error, _} = Err} -> Err;
        {atomic, W}                -> {ok, W};
        {aborted, Reason}          -> {error, Reason}
    end;
advance_step(_WorkflowId, _Outcome) ->
    {error, invalid_step_transition}.

%% @doc Abandon an in-progress or pending workflow.
-spec abandon_workflow(uuid()) -> {ok, #kyc_workflow{}} | {error, atom()}.
abandon_workflow(WorkflowId) ->
    F = fun() ->
        case mnesia:read(kyc_workflow, WorkflowId, write) of
            [] ->
                {error, not_found};
            [W] when W#kyc_workflow.status =:= completed;
                     W#kyc_workflow.status =:= abandoned ->
                {error, invalid_workflow_status};
            [W] ->
                Now = erlang:system_time(millisecond),
                W2 = W#kyc_workflow{status = abandoned, updated_at = Now},
                mnesia:write(kyc_workflow, W2, write),
                W2
        end
    end,
    case mnesia:transaction(F) of
        {atomic, {error, _} = Err} -> Err;
        {atomic, W}                -> {ok, W};
        {aborted, Reason}          -> {error, Reason}
    end.

%% @doc Get all steps for a workflow, ordered by sequence_order.
-spec get_steps(uuid()) -> {ok, [#kyc_step{}]} | {error, not_found}.
get_steps(WorkflowId) ->
    case mnesia:dirty_read(kyc_workflow, WorkflowId) of
        [] ->
            {error, not_found};
        [_W] ->
            Steps = mnesia:dirty_index_read(kyc_step, WorkflowId, workflow_id),
            Sorted = lists:sort(fun(A, B) ->
                A#kyc_step.sequence_order =< B#kyc_step.sequence_order
            end, Steps),
            {ok, Sorted}
    end.

%% Internal

-spec build_default_steps(uuid(), timestamp_ms()) -> [#kyc_step{}].
build_default_steps(WorkflowId, Now) ->
    StepDefs = [
        {1, <<"Document Collection">>,  document_collection},
        {2, <<"Identity Check">>,        identity_check},
        {3, <<"Sanctions Screening">>,   sanctions_screening},
        {4, <<"Risk Assessment">>,       risk_assessment},
        {5, <<"Approval">>,              approval}
    ],
    [#kyc_step{
        step_id        = uuid:get_v4_urandom(),
        workflow_id    = WorkflowId,
        name           = StepName,
        step_type      = StepType,
        sequence_order = Order,
        status         = pending,
        data           = #{},
        completed_at   = undefined,
        created_at     = Now
    } || {Order, StepName, StepType} <- StepDefs].

-spec advance_to_next_step(#kyc_workflow{}, timestamp_ms()) -> #kyc_workflow{}.
advance_to_next_step(W, Now) ->
    AllStepIds = W#kyc_workflow.step_ids,
    CurrentStepId = W#kyc_workflow.current_step_id,
    case next_step_id(CurrentStepId, AllStepIds) of
        none ->
            W2 = W#kyc_workflow{
                status       = completed,
                completed_at = Now,
                updated_at   = Now
            },
            mnesia:write(kyc_workflow, W2, write),
            W2;
        NextStepId ->
            case mnesia:read(kyc_step, NextStepId, write) of
                [] ->
                    W;
                [NextStep] ->
                    NextStep2 = NextStep#kyc_step{status = in_progress},
                    mnesia:write(kyc_step, NextStep2, write),
                    W2 = W#kyc_workflow{
                        current_step_id = NextStepId,
                        updated_at      = Now
                    },
                    mnesia:write(kyc_workflow, W2, write),
                    W2
            end
    end.

-spec next_step_id(uuid(), [uuid()]) -> uuid() | none.
next_step_id(_Current, []) ->
    none;
next_step_id(Current, [Current | []]) ->
    none;
next_step_id(Current, [Current | [Next | _]]) ->
    Next;
next_step_id(Current, [_ | Rest]) ->
    next_step_id(Current, Rest).
