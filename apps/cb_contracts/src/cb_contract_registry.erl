%% @doc Contract deployment, versioning, and migration controls.
-module(cb_contract_registry).

-include_lib("cb_contracts/include/cb_contracts.hrl").

-export([
    create_contract/1,
    list_contracts/0,
    get_contract/1,
    deploy_version/4,
    list_versions/1,
    get_version/2,
    activate_version/2,
    create_migration/6,
    list_migrations/1
]).

-spec create_contract(map()) -> {ok, #contract_definition{}} | {error, atom()}.
create_contract(Attrs) when is_map(Attrs) ->
    ContractId = maps:get(contract_id, Attrs, undefined),
    Name = maps:get(name, Attrs, undefined),
    Domain = maps:get(domain, Attrs, <<"general">>),
    OwnerRole = maps:get(owner_role, Attrs, <<"product_admin">>),
    case {ContractId, Name} of
        {C, N} when is_binary(C), is_binary(N) ->
            Now = now_ms(),
            Contract = #contract_definition{
                contract_id = ContractId,
                name = Name,
                domain = Domain,
                owner_role = OwnerRole,
                status = active,
                active_version = undefined,
                created_at = Now,
                updated_at = Now
            },
            case mnesia:transaction(fun() ->
                case mnesia:read(contract_definition, ContractId, write) of
                    [] -> mnesia:write(Contract), {ok, Contract};
                    [_] -> {error, idempotency_conflict}
                end
            end) of
                {atomic, Result} -> Result;
                {aborted, _} -> {error, database_error}
            end;
        _ ->
            {error, missing_required_field}
    end;
create_contract(_) ->
    {error, invalid_contract_schema}.

-spec list_contracts() -> [#contract_definition{}].
list_contracts() ->
    mnesia:dirty_select(contract_definition, [{'_', [], ['$_']}]).

-spec get_contract(binary()) -> {ok, #contract_definition{}} | {error, contract_not_found}.
get_contract(ContractId) when is_binary(ContractId) ->
    case mnesia:dirty_read(contract_definition, ContractId) of
        [Contract] -> {ok, Contract};
        [] -> {error, contract_not_found}
    end.

-spec deploy_version(binary(), binary(), map(), binary() | undefined) ->
    {ok, #contract_version{}} | {error, atom()}.
deploy_version(ContractId, Version, ContractPayload, CreatedBy)
        when is_binary(ContractId), is_binary(Version), is_map(ContractPayload) ->
    case cb_contract_validator:validate_contract(ContractPayload) of
        {ok, _} ->
            case get_contract(ContractId) of
                {ok, _Contract} ->
                    Now = now_ms(),
                    VersionRec = #contract_version{
                        version_id = new_id(),
                        contract_id = ContractId,
                        version = Version,
                        dsl_version = maps:get(dsl_version, ContractPayload, <<"1.0">>),
                        status = draft,
                        contract_payload = ContractPayload,
                        checksum = checksum(ContractPayload),
                        created_by = CreatedBy,
                        created_at = Now,
                        updated_at = Now,
                        migration_from = undefined
                    },
                    F = fun() ->
                        Existing = mnesia:index_read(contract_version, ContractId,
                                                     #contract_version.contract_id),
                        case has_version(Version, Existing) of
                            true -> {error, idempotency_conflict};
                            false ->
                                mnesia:write(VersionRec),
                                {ok, VersionRec}
                        end
                    end,
                    case mnesia:transaction(F) of
                        {atomic, Result} -> Result;
                        {aborted, _} -> {error, database_error}
                    end;
                {error, contract_not_found} ->
                    {error, contract_not_found}
            end;
        {error, Reason} ->
            {error, Reason}
    end;
deploy_version(_, _, _, _) ->
    {error, invalid_contract_schema}.

-spec list_versions(binary()) -> [#contract_version{}].
list_versions(ContractId) when is_binary(ContractId) ->
    Versions = mnesia:dirty_index_read(contract_version, ContractId,
                                       #contract_version.contract_id),
    lists:sort(
      fun(A, B) -> A#contract_version.created_at >= B#contract_version.created_at end,
      Versions).

-spec get_version(binary(), binary()) -> {ok, #contract_version{}} | {error, contract_version_not_found}.
get_version(ContractId, Version) when is_binary(ContractId), is_binary(Version) ->
    Versions = list_versions(ContractId),
    case lists:dropwhile(fun(V) -> V#contract_version.version =/= Version end, Versions) of
        [Match | _] -> {ok, Match};
        [] -> {error, contract_version_not_found}
    end.

-spec activate_version(binary(), binary()) -> {ok, #contract_definition{}} | {error, atom()}.
activate_version(ContractId, Version) when is_binary(ContractId), is_binary(Version) ->
    F = fun() ->
        case mnesia:read(contract_definition, ContractId, write) of
            [] ->
                {error, contract_not_found};
            [Contract] ->
                Versions = mnesia:index_read(contract_version, ContractId,
                                             #contract_version.contract_id),
                case pick_version(Version, Versions) of
                    {error, contract_version_not_found} ->
                        {error, contract_version_not_found};
                    {ok, ActiveVersion} ->
                        deactivate_versions(Versions),
                        UpdatedVersion = ActiveVersion#contract_version{
                            status = active,
                            updated_at = now_ms()
                        },
                        UpdatedContract = Contract#contract_definition{
                            active_version = Version,
                            updated_at = now_ms()
                        },
                        mnesia:write(UpdatedVersion),
                        mnesia:write(UpdatedContract),
                        {ok, UpdatedContract}
                end
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _} -> {error, database_error}
    end.

-spec create_migration(binary(), binary(), binary(), compatible | transform | manual,
                       binary() | undefined, binary() | undefined) ->
    {ok, #contract_migration{}} | {error, atom()}.
create_migration(ContractId, FromVersion, ToVersion, Strategy, Notes, CreatedBy)
        when is_binary(ContractId), is_binary(FromVersion), is_binary(ToVersion) ->
    case {get_version(ContractId, FromVersion), get_version(ContractId, ToVersion)} of
        {{ok, _}, {ok, _}} ->
            Migration = #contract_migration{
                migration_id = new_id(),
                contract_id = ContractId,
                from_version = FromVersion,
                to_version = ToVersion,
                strategy = Strategy,
                notes = Notes,
                created_by = CreatedBy,
                created_at = now_ms()
            },
            case mnesia:transaction(fun() -> mnesia:write(Migration), {ok, Migration} end) of
                {atomic, Result} -> Result;
                {aborted, _} -> {error, database_error}
            end;
        {{error, _}, _} ->
            {error, contract_version_not_found};
        {_, {error, _}} ->
            {error, contract_version_not_found}
    end;
create_migration(_, _, _, _, _, _) ->
    {error, invalid_parameters}.

-spec list_migrations(binary()) -> [#contract_migration{}].
list_migrations(ContractId) when is_binary(ContractId) ->
    Migrations = mnesia:dirty_index_read(contract_migration, ContractId,
                                         #contract_migration.contract_id),
    lists:sort(
      fun(A, B) -> A#contract_migration.created_at >= B#contract_migration.created_at end,
      Migrations).

has_version(_Version, []) -> false;
has_version(Version, [V | Rest]) ->
    case V#contract_version.version =:= Version of
        true -> true;
        false -> has_version(Version, Rest)
    end.

pick_version(_Version, []) ->
    {error, contract_version_not_found};
pick_version(Version, [V | Rest]) ->
    case V#contract_version.version =:= Version of
        true -> {ok, V};
        false -> pick_version(Version, Rest)
    end.

deactivate_versions([]) ->
    ok;
deactivate_versions([V | Rest]) ->
    V2 = V#contract_version{status = draft, updated_at = now_ms()},
    mnesia:write(V2),
    deactivate_versions(Rest).

checksum(Payload) ->
    Hash = crypto:hash(sha256, term_to_binary(Payload)),
    iolist_to_binary([io_lib:format("~2.16.0b", [B]) || <<B>> <= Hash]).

now_ms() ->
    erlang:system_time(millisecond).

new_id() ->
    uuid:uuid_to_string(uuid:get_v4(), binary_standard).
