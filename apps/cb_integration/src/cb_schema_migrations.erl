%% @doc Schema versioning and automated migration tooling with rollback support.
%%
%% Migrations are executed in ascending version order and persisted in
%% schema_version and schema_migration_event tables.
-module(cb_schema_migrations).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([target_version/0, current_version/0, status/0,
         migrate/0, migrate_to/1, rollback_to/1]).

-type migration_version() :: non_neg_integer().

-spec target_version() -> pos_integer().
target_version() ->
    1.

-spec current_version() -> migration_version().
current_version() ->
    case mnesia:dirty_read(schema_version, <<"core">>) of
        [#schema_version{version = V}] when is_integer(V), V >= 0 -> V;
        _ -> 0
    end.

-spec status() -> map().
status() ->
    Current = current_version(),
    Target = target_version(),
    #{
        current_version => Current,
        target_version => Target,
        pending_versions => [V || {V, _, _, _} <- migrations(), V > Current, V =< Target],
        history => history(25)
    }.

-spec migrate() -> {ok, map()} | {error, term()}.
migrate() ->
    migrate_to(target_version()).

-spec migrate_to(migration_version()) -> {ok, map()} | {error, term()}.
migrate_to(Target) when is_integer(Target), Target >= 0 ->
    Current = current_version(),
    case Target < Current of
        true ->
            {error, target_below_current};
        false ->
            case Target =< target_version() of
                false ->
                    {error, unsupported_target_version};
                true ->
                    apply_up(Current + 1, Target)
            end
    end;
migrate_to(_) ->
    {error, invalid_parameters}.

-spec rollback_to(migration_version()) -> {ok, map()} | {error, term()}.
rollback_to(Target) when is_integer(Target), Target >= 0 ->
    Current = current_version(),
    case Target > Current of
        true ->
            {error, target_above_current};
        false ->
            apply_down(Current, Target)
    end;
rollback_to(_) ->
    {error, invalid_parameters}.

apply_up(Version, Target) when Version > Target ->
    {ok, status()};
apply_up(Version, Target) ->
    case migration_by_version(Version) of
        {ok, {_Version, _Name, Up, _Down}} ->
            FromVersion = current_version(),
            case Up() of
                ok ->
                    ok = write_schema_version(Version),
                    ok = write_event(FromVersion, Version, <<"up">>, <<"applied">>, #{}),
                    apply_up(Version + 1, Target);
                {error, Reason} ->
                    _ = write_event(FromVersion, FromVersion, <<"up">>, <<"failed">>, #{
                        migration_version => Version,
                        reason => normalize_reason(Reason)
                    }),
                    {error, Reason}
            end;
        {error, not_found} ->
            {error, unsupported_target_version}
    end.

apply_down(Current, Target) when Current =< Target ->
    {ok, status()};
apply_down(Current, Target) ->
    case migration_by_version(Current) of
        {ok, {_Version, _Name, _Up, Down}} ->
            case Down() of
                ok ->
                    NewVersion = Current - 1,
                    ok = write_schema_version(NewVersion),
                    ok = write_event(Current, NewVersion, <<"down">>, <<"rolled_back">>, #{}),
                    apply_down(NewVersion, Target);
                {error, Reason} ->
                    _ = write_event(Current, Current, <<"down">>, <<"failed">>, #{
                        migration_version => Current,
                        reason => normalize_reason(Reason)
                    }),
                    {error, Reason}
            end;
        {error, not_found} ->
            {error, unsupported_target_version}
    end.

-spec migrations() -> [{pos_integer(), binary(), fun(() -> ok | {error, term()}), fun(() -> ok | {error, term()})}].
migrations() ->
    [
        {1, <<"operations_index_hardening">>, fun migration_1_up/0, fun migration_1_down/0}
    ].

migration_by_version(Version) ->
    case lists:keyfind(Version, 1, migrations()) of
        false -> {error, not_found};
        Tuple -> {ok, Tuple}
    end.

migration_1_up() ->
    run_steps([
        fun() -> ensure_index(incident_response, resolved_at) end,
        fun() -> ensure_index(structured_log, status_code) end
    ]).

migration_1_down() ->
    run_steps([
        fun() -> ensure_index_deleted(incident_response, resolved_at) end,
        fun() -> ensure_index_deleted(structured_log, status_code) end
    ]).

run_steps([]) ->
    ok;
run_steps([Step | Rest]) ->
    case Step() of
        ok -> run_steps(Rest);
        {error, _} = Error -> Error
    end.

ensure_index(Table, IndexField) ->
    case mnesia:add_table_index(Table, IndexField) of
        {atomic, ok} -> ok;
        {aborted, {already_exists, _, _}} -> ok;
        {aborted, Reason} -> {error, {add_index_failed, Table, IndexField, Reason}}
    end.

ensure_index_deleted(Table, IndexField) ->
    case mnesia:del_table_index(Table, IndexField) of
        {atomic, ok} -> ok;
        {aborted, {no_exists, _, _}} -> ok;
        {aborted, Reason} -> {error, {drop_index_failed, Table, IndexField, Reason}}
    end.

write_schema_version(Version) ->
    Now = now_ms(),
    case mnesia:sync_transaction(fun() ->
        mnesia:write(#schema_version{
            id = <<"core">>,
            version = Version,
            updated_at = Now
        })
    end) of
        {atomic, ok} -> ok;
        {aborted, Reason} -> error({schema_version_write_failed, Reason})
    end.

write_event(FromVersion, ToVersion, Direction, Status, Details) ->
    Event = #schema_migration_event{
        event_id = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
        from_version = FromVersion,
        to_version = ToVersion,
        direction = Direction,
        status = Status,
        details = Details,
        applied_at = now_ms()
    },
    case mnesia:dirty_write(schema_migration_event, Event) of
        ok -> ok;
        _ -> ok
    end.

history(Limit) when is_integer(Limit), Limit > 0 ->
    Pattern = #schema_migration_event{
        event_id = '_',
        from_version = '_',
        to_version = '_',
        direction = '_',
        status = '_',
        details = '_',
        applied_at = '_'
    },
    Events = mnesia:dirty_match_object(schema_migration_event, Pattern),
    Sorted = lists:sort(
        fun(A, B) ->
            A#schema_migration_event.applied_at >= B#schema_migration_event.applied_at
        end,
        Events
    ),
    [event_to_map(E) || E <- lists:sublist(Sorted, Limit)].

event_to_map(Event) ->
    #{
        event_id => Event#schema_migration_event.event_id,
        from_version => Event#schema_migration_event.from_version,
        to_version => Event#schema_migration_event.to_version,
        direction => Event#schema_migration_event.direction,
        status => Event#schema_migration_event.status,
        details => Event#schema_migration_event.details,
        applied_at => Event#schema_migration_event.applied_at
    }.

normalize_reason(Reason) when is_atom(Reason) ->
    atom_to_binary(Reason, utf8);
normalize_reason(Reason) when is_binary(Reason) ->
    Reason;
normalize_reason(Reason) ->
    iolist_to_binary(io_lib:format("~p", [Reason])).

now_ms() ->
    erlang:system_time(millisecond).