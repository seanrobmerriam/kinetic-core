%% @doc Connector versioning and rollback.
%%
%% Before a connector is updated, a version snapshot can be created via
%% snapshot_version/1. Snapshots are immutable and only one is marked active
%% at a time. rollback/2 restores a connector's config from any prior snapshot
%% and marks that snapshot as the active version.
-module(cb_connector_versions).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    snapshot_version/1,
    list_versions/1,
    get_version/1,
    rollback/2
]).

%% ---------------------------------------------------------------------------
%% Public API
%% ---------------------------------------------------------------------------

-spec snapshot_version(uuid()) -> {ok, #connector_version{}} | {error, term()}.
snapshot_version(ConnectorId) ->
    case mnesia:dirty_read(connector_definition, ConnectorId) of
        [] ->
            {error, not_found};
        [Connector] ->
            VersionId = uuid:get_v4_urandom(),
            Now = erlang:system_time(millisecond),
            Snapshot = #connector_version{
                version_id      = VersionId,
                connector_id    = ConnectorId,
                version         = Connector#connector_definition.version,
                module          = Connector#connector_definition.module,
                capabilities    = Connector#connector_definition.capabilities,
                config_snapshot = Connector#connector_definition.config_schema,
                is_active       = true,
                created_at      = Now,
                rolled_back_at  = undefined
            },
            F = fun() ->
                deactivate_existing_versions(ConnectorId),
                mnesia:write(Snapshot)
            end,
            case mnesia:transaction(F) of
                {atomic, ok} -> {ok, Snapshot};
                {aborted, Reason} -> {error, Reason}
            end
    end.

-spec list_versions(uuid()) -> [#connector_version{}].
list_versions(ConnectorId) ->
    Versions = mnesia:dirty_index_read(connector_version, ConnectorId, #connector_version.connector_id),
    lists:sort(fun(A, B) -> A#connector_version.created_at >= B#connector_version.created_at end, Versions).

-spec get_version(uuid()) -> {ok, #connector_version{}} | {error, not_found}.
get_version(VersionId) ->
    case mnesia:dirty_read(connector_version, VersionId) of
        [Version] -> {ok, Version};
        []        -> {error, not_found}
    end.

-spec rollback(uuid(), uuid()) -> {ok, #connector_definition{}} | {error, term()}.
rollback(ConnectorId, VersionId) ->
    F = fun() ->
        case mnesia:read(connector_definition, ConnectorId, write) of
            [] ->
                {error, connector_not_found};
            [Connector] ->
                case mnesia:read(connector_version, VersionId, write) of
                    [] ->
                        {error, version_not_found};
                    [#connector_version{connector_id = ConnectorId} = Snap] ->
                        Now = erlang:system_time(millisecond),
                        Restored = Connector#connector_definition{
                            version       = Snap#connector_version.version,
                            module        = Snap#connector_version.module,
                            capabilities  = Snap#connector_version.capabilities,
                            config_schema = Snap#connector_version.config_snapshot,
                            updated_at    = Now
                        },
                        deactivate_existing_versions(ConnectorId),
                        MarkedActive = Snap#connector_version{
                            is_active      = true,
                            rolled_back_at = Now
                        },
                        mnesia:write(Restored),
                        mnesia:write(MarkedActive),
                        {ok, Restored};
                    [#connector_version{}] ->
                        {error, version_connector_mismatch}
                end
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, Reason} -> {error, Reason}
    end.

%% ---------------------------------------------------------------------------
%% Internal
%% ---------------------------------------------------------------------------

-spec deactivate_existing_versions(uuid()) -> ok.
deactivate_existing_versions(ConnectorId) ->
    Versions = mnesia:dirty_index_read(connector_version, ConnectorId, #connector_version.connector_id),
    lists:foreach(fun(V) ->
        mnesia:write(V#connector_version{is_active = false})
    end, Versions),
    ok.
