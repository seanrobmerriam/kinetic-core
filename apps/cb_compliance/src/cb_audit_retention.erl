%% @doc Audit Retention Policy Module
%%
%% Manages configurable retention periods for audit and ledger entries.
%% Supports per-resource-type policies and provides both immediate application
%% and scheduled (job-based) retention enforcement.
%%
-module(cb_audit_retention).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    set_retention_policy/2,
    get_retention_policy/1,
    apply_retention_policies/0,
    apply_retention_policy/1
]).

-define(TABLE, audit_retention_policy).

-type resource_type() :: ledger_entry | transaction | party_audit | api_usage_event.
-type retention_days() :: non_neg_integer().

-record(audit_retention_policy, {
    resource     :: resource_type(),
    retention_days :: retention_days(),
    created_at   :: timestamp_ms(),
    updated_at   :: timestamp_ms()
}).

%% @doc Set or update the retention policy for a resource type.
%%
%% Setting retention_days to 0 means forever (no automatic deletion).
%%
-spec set_retention_policy(Resource :: resource_type(), RetentionDays :: retention_days()) ->
    ok | {error, atom()}.
set_retention_policy(Resource, RetentionDays) when is_atom(Resource), is_integer(RetentionDays), RetentionDays >= 0 ->
    F = fun() ->
        Now = erlang:system_time(millisecond),
        Policy = #audit_retention_policy{
            resource = Resource,
            retention_days = RetentionDays,
            created_at = Now,
            updated_at = Now
        },
        mnesia:write(Policy)
    end,
    case mnesia:transaction(F) of
        {atomic, ok} -> ok;
        {aborted, Reason} -> {error, Reason}
    end.

%% @doc Get the current retention policy for a resource type.
%%
-spec get_retention_policy(Resource :: resource_type()) ->
    {ok, retention_days()} | {error, not_found}.
get_retention_policy(Resource) ->
    F = fun() ->
        case mnesia:read({?TABLE, Resource}) of
            [#audit_retention_policy{retention_days = Days}] ->
                {ok, Days};
            [] ->
                {error, not_found}
        end
    end,
    mnesia:transaction(F).

%% @doc Apply all retention policies.
%%
%% Iterates through all configured policies and deletes records older than
%% their respective retention periods. This function is intended to be called
%% by a scheduled job.
%%
%% Returns the total count of deleted records.
%%
-spec apply_retention_policies() -> {ok, #{resource_type() => non_neg_integer()}}.
apply_retention_policies() ->
    F = fun() -> mnesia:all_keys(?TABLE) end,
    case mnesia:transaction(F) of
        {atomic, Resources} ->
            Results = [apply_retention_policy(R) || R <- Resources],
            {ok, maps:from_list(Results)};
        {aborted, Reason} ->
            {error, Reason}
    end.

%% @doc Apply retention policy for a single resource type.
%%
%% Deletes records of the given resource type that are older than the
%% configured retention period. Uses the record's created_at field
%% as the age threshold.
%%
-spec apply_retention_policy(Resource :: resource_type()) ->
    {Resource :: resource_type(), DeletedCount :: non_neg_integer()}.
apply_retention_policy(Resource) ->
    F = fun() ->
        Now = erlang:system_time(millisecond),
        case get_retention_policy(Resource) of
            {ok, RetentionDays} when RetentionDays > 0 ->
                AgeMs = RetentionDays * 86400000,  %% days to ms
                Threshold = Now - AgeMs,
                %% For transaction table - delete old records
                TableName = resource_to_table(Resource),
                MatchSpec = [{#transaction{_ = '_', created_at = '$1'}, [{'<', '$1', Threshold}], ['$_']}],
                _Deleted = mnesia:select(TableName, MatchSpec, write),
                {deleted_count, Count} = mnesia:select(TableName, MatchSpec, [write]),
                Count;
            _ ->
                0
        end
    end,
    {atomic, Count} = mnesia:transaction(F),
    {Resource, Count}.

%% @private Map resource type atom to actual Mnesia table name
-spec resource_to_table(resource_type()) -> atom().
resource_to_table(ledger_entry) -> ledger_entry;
resource_to_table(transaction) -> transaction;
resource_to_table(party_audit) -> party_audit;
resource_to_table(api_usage_event) -> api_usage_event.