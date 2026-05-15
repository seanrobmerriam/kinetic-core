%% @doc Audit replay support for persisted contract executions.
-module(cb_contract_replay).

-include_lib("cb_contracts/include/cb_contracts.hrl").

-export([
    get_execution_trace/1,
    list_execution_traces/2,
    replay_execution/2
]).

-spec get_execution_trace(binary()) -> {ok, #contract_execution_trace{}} | {error, execution_not_found}.
get_execution_trace(ExecutionId) when is_binary(ExecutionId) ->
    case mnesia:dirty_read(contract_execution_trace, ExecutionId) of
        [Trace] -> {ok, Trace};
        [] -> {error, execution_not_found}
    end.

-spec list_execution_traces(binary(), pos_integer()) -> [#contract_execution_trace{}].
list_execution_traces(ContractId, Limit) when is_binary(ContractId), is_integer(Limit), Limit > 0 ->
    Traces = mnesia:dirty_index_read(contract_execution_trace, ContractId,
                                     #contract_execution_trace.contract_id),
    Sorted = lists:sort(
      fun(A, B) -> A#contract_execution_trace.created_at >= B#contract_execution_trace.created_at end,
      Traces),
    lists:sublist(Sorted, Limit).

-spec replay_execution(binary(), map() | undefined) -> {ok, map()} | {error, atom()}.
replay_execution(ExecutionId, ContextOverride) ->
    case get_execution_trace(ExecutionId) of
        {ok, Trace} ->
            ContractId = Trace#contract_execution_trace.contract_id,
            Version = Trace#contract_execution_trace.contract_version,
            case cb_contracts:get_version(ContractId, Version) of
                {ok, VersionRec} ->
                    Payload0 = VersionRec#contract_version.contract_payload,
                    Payload = Payload0#{contract_id => ContractId,
                                        version => VersionRec#contract_version.version},
                    Context = case ContextOverride of
                        undefined -> Trace#contract_execution_trace.context_snapshot;
                        Ctx when is_map(Ctx) -> Ctx
                    end,
                    Authz = #{request_id => <<"replay">>,
                              timeout_ms => 50,
                              capabilities => [can_emit_event,
                                               can_enqueue_review,
                                               can_set_decision_fields]},
                    case cb_contracts:execute(Payload, Context, Authz) of
                        {ok, Decision, NewTrace} ->
                            NewHash = maps:get(decision_hash, NewTrace, undefined),
                            OldHash = Trace#contract_execution_trace.decision_hash,
                            {ok, #{replay_result => ok,
                                   hash_match => NewHash =:= OldHash,
                                   execution_id => ExecutionId,
                                   old_decision_hash => OldHash,
                                   new_decision_hash => NewHash,
                                   decision => Decision}};
                        {error, Reason, NewTrace} ->
                            {ok, #{replay_result => error,
                                   reason => Reason,
                                   execution_id => ExecutionId,
                                   trace => NewTrace}}
                    end;
                {error, _} ->
                    {error, contract_version_not_found}
            end;
        {error, _} ->
            {error, execution_not_found}
    end.
