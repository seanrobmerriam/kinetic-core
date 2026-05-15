%% @doc Public API for smart contract validation and bounded execution.
-module(cb_contracts).

-include_lib("cb_contracts/include/cb_contracts.hrl").

-export([
    validate_contract/1,
    execute/2,
    execute/3,
    create_contract/1,
    list_contracts/0,
    get_contract/1,
    deploy_version/4,
    list_versions/1,
    get_version/2,
    activate_version/2,
    create_migration/6,
    list_migrations/1,
    create_experiment/4,
    list_experiments/1,
    get_experiment/2,
    activate_experiment/2,
    stop_experiment/2,
    assign_variant/3,
    get_execution_trace/1,
    list_execution_traces/2,
    replay_execution/2
]).

-define(DEFAULT_TIMEOUT_MS, 50).

-spec validate_contract(map()) -> {ok, map()} | {error, atom()}.
validate_contract(Contract) ->
    cb_contract_validator:validate_contract(Contract).

-spec create_contract(map()) -> {ok, #contract_definition{}} | {error, atom()}.
create_contract(Attrs) ->
    cb_contract_registry:create_contract(Attrs).

-spec list_contracts() -> [#contract_definition{}].
list_contracts() ->
    cb_contract_registry:list_contracts().

-spec get_contract(binary()) -> {ok, #contract_definition{}} | {error, contract_not_found}.
get_contract(ContractId) ->
    cb_contract_registry:get_contract(ContractId).

-spec deploy_version(binary(), binary(), map(), binary() | undefined) ->
    {ok, #contract_version{}} | {error, atom()}.
deploy_version(ContractId, Version, ContractPayload, CreatedBy) ->
    cb_contract_registry:deploy_version(ContractId, Version, ContractPayload, CreatedBy).

-spec list_versions(binary()) -> [#contract_version{}].
list_versions(ContractId) ->
    cb_contract_registry:list_versions(ContractId).

-spec get_version(binary(), binary()) -> {ok, #contract_version{}} | {error, contract_version_not_found}.
get_version(ContractId, Version) ->
    cb_contract_registry:get_version(ContractId, Version).

-spec activate_version(binary(), binary()) -> {ok, #contract_definition{}} | {error, atom()}.
activate_version(ContractId, Version) ->
    cb_contract_registry:activate_version(ContractId, Version).

-spec create_migration(binary(), binary(), binary(), compatible | transform | manual,
                       binary() | undefined, binary() | undefined) ->
    {ok, #contract_migration{}} | {error, atom()}.
create_migration(ContractId, FromVersion, ToVersion, Strategy, Notes, CreatedBy) ->
    cb_contract_registry:create_migration(
      ContractId, FromVersion, ToVersion, Strategy, Notes, CreatedBy).

-spec list_migrations(binary()) -> [#contract_migration{}].
list_migrations(ContractId) ->
    cb_contract_registry:list_migrations(ContractId).

-spec create_experiment(binary(), binary(), [map()], binary() | undefined) ->
    {ok, #contract_experiment{}} | {error, atom()}.
create_experiment(ContractId, Name, Variants, CreatedBy) ->
    cb_contract_experiments:create_experiment(ContractId, Name, Variants, CreatedBy).

-spec list_experiments(binary()) -> [#contract_experiment{}].
list_experiments(ContractId) ->
    cb_contract_experiments:list_experiments(ContractId).

-spec get_experiment(binary(), binary()) -> {ok, #contract_experiment{}} | {error, experiment_not_found}.
get_experiment(ContractId, ExperimentId) ->
    cb_contract_experiments:get_experiment(ContractId, ExperimentId).

-spec activate_experiment(binary(), binary()) -> {ok, #contract_experiment{}} | {error, atom()}.
activate_experiment(ContractId, ExperimentId) ->
    cb_contract_experiments:activate_experiment(ContractId, ExperimentId).

-spec stop_experiment(binary(), binary()) -> {ok, #contract_experiment{}} | {error, atom()}.
stop_experiment(ContractId, ExperimentId) ->
    cb_contract_experiments:stop_experiment(ContractId, ExperimentId).

-spec assign_variant(binary(), binary(), binary()) -> {ok, binary(), map()} | {error, atom()}.
assign_variant(ContractId, ExperimentId, SubjectKey) ->
    cb_contract_experiments:assign_variant(ContractId, ExperimentId, SubjectKey).

-spec get_execution_trace(binary()) -> {ok, #contract_execution_trace{}} | {error, execution_not_found}.
get_execution_trace(ExecutionId) ->
    cb_contract_replay:get_execution_trace(ExecutionId).

-spec list_execution_traces(binary(), pos_integer()) -> [#contract_execution_trace{}].
list_execution_traces(ContractId, Limit) ->
    cb_contract_replay:list_execution_traces(ContractId, Limit).

-spec replay_execution(binary(), map() | undefined) -> {ok, map()} | {error, atom()}.
replay_execution(ExecutionId, ContextOverride) ->
    cb_contract_replay:replay_execution(ExecutionId, ContextOverride).

-spec execute(map(), map()) ->
    {ok, map(), map()} | {error, atom(), map()}.
execute(Contract, Context) ->
    execute(Contract, Context, #{}).

-spec execute(map(), map(), map()) ->
    {ok, map(), map()} | {error, atom(), map()}.
execute(Contract, Context, Authz) when is_map(Contract), is_map(Context), is_map(Authz) ->
    RequestId = maps:get(request_id, Authz, undefined),
    Trace0 = cb_contract_audit:new_trace(Contract, Context, RequestId),
    case cb_contract_validator:validate_contract(Contract) of
        {ok, ValidContract} ->
            TimeoutMs = maps:get(timeout_ms, Authz, ?DEFAULT_TIMEOUT_MS),
            Runner = fun() -> cb_contract_eval:evaluate(ValidContract, Context, Authz, Trace0) end,
            case cb_contract_sandbox:run(Runner, TimeoutMs) of
                {ok, {ok, Decision, Trace1}, _DurationUs} ->
                    Trace2 = cb_contract_audit:finish_ok(Trace1, Decision),
                    _ = cb_contract_audit:persist_trace(Trace2),
                    {ok, Decision, Trace2};
                {ok, {error, Reason, Trace1}, _DurationUs} ->
                    Trace2 = cb_contract_audit:finish_error(Trace1, Reason),
                    _ = cb_contract_audit:persist_trace(Trace2),
                    {error, Reason, Trace2};
                {ok, {error, {_Class, _Reason, _Stack}}, _DurationUs} ->
                    Trace2 = cb_contract_audit:finish_error(Trace0, side_effect_failed),
                    _ = cb_contract_audit:persist_trace(Trace2),
                    {error, side_effect_failed, Trace2};
                {ok, _Unexpected, _DurationUs} ->
                    Trace2 = cb_contract_audit:finish_error(Trace0, side_effect_failed),
                    _ = cb_contract_audit:persist_trace(Trace2),
                    {error, side_effect_failed, Trace2};
                {error, execution_budget_exceeded, _DurationUs} ->
                    Trace2 = cb_contract_audit:finish_error(Trace0, execution_budget_exceeded),
                    _ = cb_contract_audit:persist_trace(Trace2),
                    {error, execution_budget_exceeded, Trace2};
                {error, {sandbox_crash, _CrashReason}, _DurationUs} ->
                    Trace2 = cb_contract_audit:finish_error(Trace0, side_effect_failed),
                    _ = cb_contract_audit:persist_trace(Trace2),
                    {error, side_effect_failed, Trace2}
            end;
        {error, Reason} ->
            Trace2 = cb_contract_audit:finish_error(Trace0, Reason),
            _ = cb_contract_audit:persist_trace(Trace2),
            {error, Reason, Trace2}
    end;
execute(_Contract, _Context, _Authz) ->
    Trace0 = cb_contract_audit:new_trace(#{}, #{}, undefined),
    Trace2 = cb_contract_audit:finish_error(Trace0, invalid_contract_schema),
    {error, invalid_contract_schema, Trace2}.
