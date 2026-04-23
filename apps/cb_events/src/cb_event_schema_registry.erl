%% @doc Event Schema Registry (TASK-058)
%%
%% Maintains a versioned catalogue of event type schemas.  Each registration
%% stores a schema map and a compatibility policy.  Compatibility is enforced
%% on every new version registration:
%%
%% <ul>
%%   <li><b>backward</b> — new version must be readable by consumers of the
%%       previous version (new optional fields only).</li>
%%   <li><b>forward</b>  — old consumers must be able to read new version data
%%       (only field additions allowed in current version).</li>
%%   <li><b>full</b>     — both backward and forward.</li>
%%   <li><b>none</b>     — no compatibility guarantee; any change is allowed.</li>
%% </ul>
%%
%% == Mnesia table ==
%% `event_schema_version' — keyed by schema_id (UUID).
-module(cb_event_schema_registry).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([register/1, get_schema/2, list_versions/1, check_compatibility/3,
         latest_version/1]).

%%--------------------------------------------------------------------
%% Public API
%%--------------------------------------------------------------------

%% @doc Register a new event schema version.
%%
%% `Params' must include: event_type (binary), version (pos_integer),
%% schema (map with "fields" key), compatibility (schema_compatibility()).
%%
%% Returns `{error, incompatible_schema}' if a previous version exists and
%% the new schema violates the declared compatibility policy.
-spec register(map()) -> {ok, binary()} | {error, atom()}.
register(Params) ->
    EventType    = maps:get(event_type, Params),
    Version      = maps:get(version, Params),
    Schema       = maps:get(schema, Params),
    Compatibility = maps:get(compatibility, Params, backward),
    case validate_schema_format(Schema) of
        ok ->
            case latest_version(EventType) of
                {ok, Prev} ->
                    case check_compatibility(Prev#event_schema_version.schema, Schema, Compatibility) of
                        ok ->
                            do_register(EventType, Version, Schema, Compatibility);
                        {error, _} = Err ->
                            Err
                    end;
                {error, not_found} ->
                    do_register(EventType, Version, Schema, Compatibility)
            end;
        {error, _} = Err ->
            Err
    end.

%% @doc Get a specific version of an event schema.
-spec get_schema(binary(), pos_integer()) ->
    {ok, #event_schema_version{}} | {error, not_found}.
get_schema(EventType, Version) ->
    MatchSpec = [{
        #event_schema_version{schema_id = '_', event_type = EventType,
                              version = Version, schema = '_',
                              compatibility = '_', created_at = '_'},
        [], ['$_']
    }],
    case mnesia:dirty_select(event_schema_version, MatchSpec) of
        [Schema] -> {ok, Schema};
        []       -> {error, not_found};
        [H | _]  -> {ok, H}
    end.

%% @doc List all registered versions for an event type, ascending order.
-spec list_versions(binary()) -> [#event_schema_version{}].
list_versions(EventType) ->
    MatchSpec = [{
        #event_schema_version{schema_id = '_', event_type = EventType,
                              version = '_', schema = '_',
                              compatibility = '_', created_at = '_'},
        [], ['$_']
    }],
    Versions = mnesia:dirty_select(event_schema_version, MatchSpec),
    lists:sort(fun(A, B) -> A#event_schema_version.version =< B#event_schema_version.version end,
               Versions).

%% @doc Get the highest registered version for an event type.
-spec latest_version(binary()) ->
    {ok, #event_schema_version{}} | {error, not_found}.
latest_version(EventType) ->
    case lists:reverse(list_versions(EventType)) of
        [Latest | _] -> {ok, Latest};
        []           -> {error, not_found}
    end.

%% @doc Check schema compatibility between OldSchema and NewSchema.
%%
%% Compatibility rules (simplified structural check on "fields" keys):
%%   backward — NewSchema must contain all fields from OldSchema.
%%   forward  — OldSchema must contain all fields from NewSchema.
%%   full     — both conditions must hold.
%%   none     — always compatible.
-spec check_compatibility(map(), map(), schema_compatibility()) ->
    ok | {error, incompatible_schema}.
check_compatibility(_OldSchema, _NewSchema, none) ->
    ok;
check_compatibility(OldSchema, NewSchema, backward) ->
    OldFields = get_fields(OldSchema),
    NewFields = get_fields(NewSchema),
    Missing = [F || F <- OldFields, not lists:member(F, NewFields)],
    case Missing of
        [] -> ok;
        _  -> {error, incompatible_schema}
    end;
check_compatibility(OldSchema, NewSchema, forward) ->
    OldFields = get_fields(OldSchema),
    NewFields = get_fields(NewSchema),
    Added = [F || F <- NewFields, not lists:member(F, OldFields)],
    case Added of
        [] -> ok;
        _  -> {error, incompatible_schema}
    end;
check_compatibility(OldSchema, NewSchema, full) ->
    case check_compatibility(OldSchema, NewSchema, backward) of
        ok -> check_compatibility(OldSchema, NewSchema, forward);
        Err -> Err
    end.

%%--------------------------------------------------------------------
%% Internal helpers
%%--------------------------------------------------------------------

-spec validate_schema_format(map()) -> ok | {error, invalid_schema}.
validate_schema_format(Schema) when is_map(Schema) ->
    HasFields = maps:is_key(<<"fields">>, Schema) orelse maps:is_key(fields, Schema),
    case HasFields of
        true  -> ok;
        false -> {error, invalid_schema}
    end;
validate_schema_format(_) ->
    {error, invalid_schema}.

-spec do_register(binary(), pos_integer(), map(), schema_compatibility()) ->
    {ok, binary()} | {error, atom()}.
do_register(EventType, Version, Schema, Compatibility) ->
    SchemaId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
    Now      = erlang:system_time(millisecond),
    Record   = #event_schema_version{
        schema_id     = SchemaId,
        event_type    = EventType,
        version       = Version,
        schema        = Schema,
        compatibility = Compatibility,
        created_at    = Now
    },
    F = fun() -> mnesia:write(Record) end,
    case mnesia:transaction(F) of
        {atomic, ok}  -> {ok, SchemaId};
        {aborted, _}  -> {error, database_error}
    end.

-spec get_fields(map()) -> list().
get_fields(Schema) ->
    case maps:get(fields, Schema, not_found) of
        not_found -> maps:get(<<"fields">>, Schema, []);
        Fields    -> Fields
    end.
