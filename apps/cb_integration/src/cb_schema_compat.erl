%% @doc Backward compatibility enforcement for schema changes (TASK-106).
%%
%% Maintains a compile-time baseline of expected Mnesia table field-sets.
%% check/0 compares the live table attributes against the baseline and
%% returns any backward-compat violations (removed fields, renamed fields)
%% so that schema changes are caught before a migration is applied.
%%
%% A schema change is BACKWARD COMPATIBLE when:
%%   - All previously known fields still exist (no removals, no renames).
%%   - New optional fields may be added freely.
%%
%% A schema change is INCOMPATIBLE when:
%%   - One or more previously required fields are absent from the live table.
%%
%% The baseline is intentionally encoded as compile-time data so that any
%% production change to a record's field list triggers a detectable diff
%% during CI contract tests.
-module(cb_schema_compat).

-include_lib("cb_ledger/include/cb_ledger.hrl").
-include_lib("cb_events/include/cb_events.hrl").

-export([check/0, check_table/1, baseline/0, baseline_fields/1]).

-type field_name() :: atom().
-type table_name() :: atom().
-type compat_result() :: ok | {violations, [violation()]}.
-type violation()     :: {table_name(), removed_fields, [field_name()]}
                       | {table_name(), table_missing}.

-export_type([compat_result/0, violation/0]).

%% @doc Check all known tables for backward-compat violations.
%%
%% Returns `ok' when every table in the baseline has all its expected fields
%% present in the live Mnesia schema. Returns `{violations, List}' with one
%% entry per offending table otherwise.
-spec check() -> compat_result().
check() ->
    Tables = [T || {T, _} <- baseline()],
    Violations = lists:filtermap(
        fun(Table) ->
            case check_table(Table) of
                ok -> false;
                V  -> {true, V}
            end
        end,
        Tables
    ),
    case Violations of
        [] -> ok;
        _  -> {violations, Violations}
    end.

%% @doc Check a single table for backward-compat violations.
-spec check_table(table_name()) -> ok | violation().
check_table(Table) ->
    case baseline_fields(Table) of
        {error, unknown_table} ->
            ok;
        {ok, BaselineFields} ->
            case live_fields(Table) of
                {error, table_missing} ->
                    {Table, table_missing};
                {ok, LiveFields} ->
                    Removed = [F || F <- BaselineFields, not lists:member(F, LiveFields)],
                    case Removed of
                        [] -> ok;
                        _  -> {Table, removed_fields, Removed}
                    end
            end
    end.

%% @doc Return the compile-time baseline for all tracked tables.
%%
%% Each entry is {TableName, [FieldName, ...]} where field names match
%% the Erlang record field atoms defined in cb_ledger.hrl / cb_events.hrl,
%% or the inline attribute lists used in cb_schema.erl.
-spec baseline() -> [{table_name(), [field_name()]}].
baseline() ->
    [
        {party,             record_info(fields, party)},
        {account,           record_info(fields, account)},
        {transaction,       record_info(fields, transaction)},
        {ledger_entry,      record_info(fields, ledger_entry)},
        {payment_order,     record_info(fields, payment_order)},
        {exception_item,    record_info(fields, exception_item)},
        %% auth_user / auth_session / audit_log are inline in cb_schema
        {auth_user,         [user_id, email, password_hash, role, status,
                             created_at, updated_at]},
        {auth_session,      [session_id, user_id, status, expires_at,
                             created_at, updated_at, channel_type]},
        {audit_log,         [audit_id, actor_user_id, action, entity_type, entity_id,
                             metadata, created_at]},
        {event_outbox,      record_info(fields, event_outbox)},
        {webhook_subscription, record_info(fields, webhook_subscription)},
        {webhook_delivery,  record_info(fields, webhook_delivery)},
        {incident_response, record_info(fields, incident_response)},
        {structured_log,    record_info(fields, structured_log)},
        {schema_version,    record_info(fields, schema_version)},
        {schema_migration_event, record_info(fields, schema_migration_event)}
    ].

%% @doc Return the compile-time baseline fields for a single table.
-spec baseline_fields(table_name()) -> {ok, [field_name()]} | {error, unknown_table}.
baseline_fields(Table) ->
    case lists:keyfind(Table, 1, baseline()) of
        false         -> {error, unknown_table};
        {Table, Fields} -> {ok, Fields}
    end.

%%--------------------------------------------------------------------
%% Internal
%%--------------------------------------------------------------------

-spec live_fields(table_name()) -> {ok, [field_name()]} | {error, table_missing}.
live_fields(Table) ->
    case catch mnesia:table_info(Table, attributes) of
        {'EXIT', _}               -> {error, table_missing};
        Attrs when is_list(Attrs) -> {ok, Attrs};
        _                         -> {error, table_missing}
    end.
