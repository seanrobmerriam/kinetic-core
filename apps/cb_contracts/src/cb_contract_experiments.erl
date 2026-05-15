%% @doc Product variant experiments for contract versions.
-module(cb_contract_experiments).

-include_lib("cb_contracts/include/cb_contracts.hrl").

-export([
    create_experiment/4,
    list_experiments/1,
    get_experiment/2,
    activate_experiment/2,
    stop_experiment/2,
    assign_variant/3
]).

-spec create_experiment(binary(), binary(), [map()], binary() | undefined) ->
    {ok, #contract_experiment{}} | {error, atom()}.
create_experiment(ContractId, Name, Variants, CreatedBy)
        when is_binary(ContractId), is_binary(Name), is_list(Variants), Variants =/= [] ->
    case cb_contracts:get_contract(ContractId) of
        {ok, _} ->
            case validate_variants(ContractId, Variants) of
                ok ->
                    Now = now_ms(),
                    Exp = #contract_experiment{
                        experiment_id = new_id(),
                        contract_id = ContractId,
                        name = Name,
                        status = draft,
                        variants = Variants,
                        allocation_seed = new_id(),
                        created_by = CreatedBy,
                        created_at = Now,
                        updated_at = Now
                    },
                    case mnesia:transaction(fun() -> mnesia:write(Exp), {ok, Exp} end) of
                        {atomic, Result} -> Result;
                        {aborted, _} -> {error, database_error}
                    end;
                {error, _} = Error ->
                    Error
            end;
        {error, _} ->
            {error, contract_not_found}
    end;
create_experiment(_, _, _, _) ->
    {error, invalid_parameters}.

-spec list_experiments(binary()) -> [#contract_experiment{}].
list_experiments(ContractId) ->
    Exps = mnesia:dirty_index_read(contract_experiment, ContractId,
                                   #contract_experiment.contract_id),
    lists:sort(fun(A, B) -> A#contract_experiment.created_at >= B#contract_experiment.created_at end, Exps).

-spec get_experiment(binary(), binary()) -> {ok, #contract_experiment{}} | {error, experiment_not_found}.
get_experiment(ContractId, ExperimentId) ->
    case mnesia:dirty_read(contract_experiment, ExperimentId) of
        [Exp] when Exp#contract_experiment.contract_id =:= ContractId -> {ok, Exp};
        _ -> {error, experiment_not_found}
    end.

-spec activate_experiment(binary(), binary()) -> {ok, #contract_experiment{}} | {error, atom()}.
activate_experiment(ContractId, ExperimentId) ->
    update_status(ContractId, ExperimentId, active).

-spec stop_experiment(binary(), binary()) -> {ok, #contract_experiment{}} | {error, atom()}.
stop_experiment(ContractId, ExperimentId) ->
    update_status(ContractId, ExperimentId, stopped).

-spec assign_variant(binary(), binary(), binary()) -> {ok, binary(), map()} | {error, atom()}.
assign_variant(ContractId, ExperimentId, SubjectKey)
        when is_binary(ContractId), is_binary(ExperimentId), is_binary(SubjectKey) ->
    case get_experiment(ContractId, ExperimentId) of
        {ok, #contract_experiment{status = active, variants = Variants, allocation_seed = Seed}} ->
            TotalWeight = lists:sum([maps:get(weight, V, 0) || V <- Variants]),
            case TotalWeight > 0 of
                true ->
                    Slot = hash_slot(SubjectKey, Seed, TotalWeight),
                    case pick_variant(Slot, Variants) of
                        {ok, Version, Variant} ->
                            {ok, Version, Variant};
                        {error, _} = Error ->
                            Error
                    end;
                false ->
                    {error, invalid_parameters}
            end;
        {ok, _} ->
            {error, invalid_status};
        {error, _} ->
            {error, experiment_not_found}
    end.

validate_variants(_ContractId, []) ->
    ok;
validate_variants(ContractId, [Variant | Rest]) when is_map(Variant) ->
    Version = maps:get(version, Variant, undefined),
    Weight = maps:get(weight, Variant, undefined),
    case {is_binary(Version), is_integer(Weight), Weight > 0, cb_contracts:get_version(ContractId, Version)} of
        {true, true, true, {ok, _}} -> validate_variants(ContractId, Rest);
        _ -> {error, contract_version_not_found}
    end;
validate_variants(_, _) ->
    {error, invalid_parameters}.

update_status(ContractId, ExperimentId, NewStatus) ->
    F = fun() ->
        case mnesia:read(contract_experiment, ExperimentId, write) of
            [Exp] when Exp#contract_experiment.contract_id =:= ContractId ->
                Updated = Exp#contract_experiment{status = NewStatus, updated_at = now_ms()},
                mnesia:write(Updated),
                {ok, Updated};
            _ ->
                {error, experiment_not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _} -> {error, database_error}
    end.

hash_slot(SubjectKey, Seed, TotalWeight) ->
    Hash = crypto:hash(sha256, <<SubjectKey/binary, Seed/binary>>),
    <<Num:64, _/binary>> = Hash,
    (Num rem TotalWeight) + 1.

pick_variant(Slot, Variants) ->
    pick_variant(Slot, Variants, 0).

pick_variant(_Slot, [], _Acc) ->
    {error, invalid_parameters};
pick_variant(Slot, [Variant | Rest], Acc0) ->
    Weight = maps:get(weight, Variant),
    Acc1 = Acc0 + Weight,
    case Slot =< Acc1 of
        true -> {ok, maps:get(version, Variant), Variant};
        false -> pick_variant(Slot, Rest, Acc1)
    end.

now_ms() ->
    erlang:system_time(millisecond).

new_id() ->
    uuid:uuid_to_string(uuid:get_v4(), binary_standard).
