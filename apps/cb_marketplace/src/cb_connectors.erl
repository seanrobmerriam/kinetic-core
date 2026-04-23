%% @doc Connector registry — CRUD and lifecycle state machine.
%%
%% Connectors follow this lifecycle:
%%   registered → enabled → disabled → deprecated
%%
%% A connector can only be used (execute/health_check) when it is `enabled'.
%% `disabled' connectors are inactive but still registered; they can be re-enabled.
%% `deprecated' is terminal — no further transitions are permitted.
-module(cb_connectors).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    register/1,
    get/1,
    update/2,
    list/0,
    list_by_type/1,
    list_by_status/1,
    enable/1,
    disable/1,
    deprecate/1
]).

%% ---------------------------------------------------------------------------
%% Public API
%% ---------------------------------------------------------------------------

-spec register(map()) -> {ok, #connector_definition{}} | {error, term()}.
register(Attrs) ->
    ConnectorId = uuid:get_v4_urandom(),
    Now = erlang:system_time(millisecond),
    Connector = #connector_definition{
        connector_id  = ConnectorId,
        name          = maps:get(name, Attrs),
        type          = maps:get(type, Attrs),
        module        = maps:get(module, Attrs),
        status        = registered,
        version       = maps:get(version, Attrs, <<"1.0.0">>),
        capabilities  = maps:get(capabilities, Attrs, []),
        config_schema = maps:get(config_schema, Attrs, #{}),
        description   = maps:get(description, Attrs, <<"">>),
        created_at    = Now,
        updated_at    = Now
    },
    case mnesia:transaction(fun() -> mnesia:write(Connector) end) of
        {atomic, ok} -> {ok, Connector};
        {aborted, Reason} -> {error, Reason}
    end.

-spec get(uuid()) -> {ok, #connector_definition{}} | {error, not_found}.
get(ConnectorId) ->
    case mnesia:dirty_read(connector_definition, ConnectorId) of
        [Connector] -> {ok, Connector};
        []          -> {error, not_found}
    end.

-spec update(uuid(), map()) -> {ok, #connector_definition{}} | {error, term()}.
update(ConnectorId, Updates) ->
    F = fun() ->
        case mnesia:read(connector_definition, ConnectorId, write) of
            [] -> {error, not_found};
            [Connector] ->
                Updated = apply_updates(Connector, Updates),
                mnesia:write(Updated),
                {ok, Updated}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, Reason} -> {error, Reason}
    end.

-spec list() -> [#connector_definition{}].
list() ->
    mnesia:dirty_select(connector_definition, [{'_', [], ['$_']}]).

-spec list_by_type(connector_type()) -> [#connector_definition{}].
list_by_type(Type) ->
    mnesia:dirty_index_read(connector_definition, Type, #connector_definition.type).

-spec list_by_status(connector_status()) -> [#connector_definition{}].
list_by_status(Status) ->
    mnesia:dirty_index_read(connector_definition, Status, #connector_definition.status).

%% ---------------------------------------------------------------------------
%% Lifecycle transitions
%% ---------------------------------------------------------------------------

-spec enable(uuid()) -> {ok, #connector_definition{}} | {error, term()}.
enable(ConnectorId) ->
    transition(ConnectorId, enabled, [registered, disabled]).

-spec disable(uuid()) -> {ok, #connector_definition{}} | {error, term()}.
disable(ConnectorId) ->
    transition(ConnectorId, disabled, [enabled]).

-spec deprecate(uuid()) -> {ok, #connector_definition{}} | {error, term()}.
deprecate(ConnectorId) ->
    transition(ConnectorId, deprecated, [registered, enabled, disabled]).

%% ---------------------------------------------------------------------------
%% Internal
%% ---------------------------------------------------------------------------

-spec transition(uuid(), connector_status(), [connector_status()]) ->
    {ok, #connector_definition{}} | {error, term()}.
transition(ConnectorId, NewStatus, AllowedFrom) ->
    F = fun() ->
        case mnesia:read(connector_definition, ConnectorId, write) of
            [] ->
                {error, not_found};
            [#connector_definition{status = Current} = Connector] ->
                case lists:member(Current, AllowedFrom) of
                    true ->
                        Updated = Connector#connector_definition{
                            status     = NewStatus,
                            updated_at = erlang:system_time(millisecond)
                        },
                        mnesia:write(Updated),
                        {ok, Updated};
                    false ->
                        {error, {invalid_transition, Current, NewStatus}}
                end
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, Reason} -> {error, Reason}
    end.

-spec apply_updates(#connector_definition{}, map()) -> #connector_definition{}.
apply_updates(Connector, Updates) ->
    Now = erlang:system_time(millisecond),
    Connector#connector_definition{
        name          = maps:get(name, Updates, Connector#connector_definition.name),
        version       = maps:get(version, Updates, Connector#connector_definition.version),
        capabilities  = maps:get(capabilities, Updates, Connector#connector_definition.capabilities),
        config_schema = maps:get(config_schema, Updates, Connector#connector_definition.config_schema),
        description   = maps:get(description, Updates, Connector#connector_definition.description),
        updated_at    = Now
    }.
