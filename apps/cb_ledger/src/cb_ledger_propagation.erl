%% @doc Sub-second ledger propagation tracking and read freshness (TASK-070).
%%
%% Tracks read replicas (propagation_target) and per-entry propagation events
%% (propagation_event). Provides freshness queries that report whether a
%% ledger entry has propagated to all enabled targets within their SLA.
-module(cb_ledger_propagation).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    register_target/2,
    list_targets/0,
    disable_target/1,
    record_propagation/3,
    list_events_for_entry/1,
    freshness/1
]).

-spec register_target(binary(), non_neg_integer()) ->
    {ok, uuid()} | {error, term()}.
register_target(Name, SlaMs)
        when is_binary(Name), is_integer(SlaMs), SlaMs >= 0 ->
    TargetId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
    Now = erlang:system_time(millisecond),
    Record = #propagation_target{
        target_id   = TargetId,
        target_name = Name,
        sla_ms      = SlaMs,
        enabled     = true,
        created_at  = Now
    },
    case mnesia:transaction(fun() -> mnesia:write(Record) end) of
        {atomic, ok}      -> {ok, TargetId};
        {aborted, Reason} -> {error, Reason}
    end;
register_target(_, _) ->
    {error, invalid_arguments}.

-spec list_targets() -> [#propagation_target{}].
list_targets() ->
    {atomic, Targets} = mnesia:transaction(fun() ->
        mnesia:foldl(fun(T, Acc) -> [T | Acc] end, [], propagation_target)
    end),
    lists:sort(fun(A, B) -> A#propagation_target.target_name =< B#propagation_target.target_name end, Targets).

-spec disable_target(uuid()) -> ok | {error, not_found}.
disable_target(TargetId) ->
    F = fun() ->
        case mnesia:read(propagation_target, TargetId) of
            [T] -> mnesia:write(T#propagation_target{enabled = false});
            []  -> {error, not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, ok}                 -> ok;
        {atomic, {error, not_found}} -> {error, not_found};
        {aborted, Reason}            -> {error, Reason}
    end.

-spec record_propagation(uuid(), binary(), timestamp_ms()) ->
    {ok, uuid()} | {error, term()}.
record_propagation(EntryId, TargetName, PostedAt)
        when is_binary(EntryId), is_binary(TargetName), is_integer(PostedAt) ->
    EventId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
    Now = erlang:system_time(millisecond),
    Latency = max(0, Now - PostedAt),
    Event = #propagation_event{
        event_id      = EventId,
        entry_id      = EntryId,
        target_name   = TargetName,
        posted_at     = PostedAt,
        propagated_at = Now,
        latency_ms    = Latency
    },
    case mnesia:transaction(fun() -> mnesia:write(Event) end) of
        {atomic, ok}      -> {ok, EventId};
        {aborted, Reason} -> {error, Reason}
    end;
record_propagation(_, _, _) ->
    {error, invalid_arguments}.

-spec list_events_for_entry(uuid()) -> [#propagation_event{}].
list_events_for_entry(EntryId) ->
    {atomic, Events} = mnesia:transaction(fun() ->
        mnesia:index_read(propagation_event, EntryId, entry_id)
    end),
    lists:sort(fun(A, B) -> A#propagation_event.propagated_at =< B#propagation_event.propagated_at end, Events).

%% @doc Freshness check: returns a map describing per-target propagation state
%% for an entry. fresh = true iff every enabled target has at least one event
%% within its SLA window.
-spec freshness(uuid()) ->
    {ok, #{entry_id := uuid(), fresh := boolean(), targets := [map()]}}.
freshness(EntryId) ->
    Targets = [T || T <- list_targets(), T#propagation_target.enabled],
    Events  = list_events_for_entry(EntryId),
    PerTarget = lists:map(
        fun(T) ->
            Name = T#propagation_target.target_name,
            Sla  = T#propagation_target.sla_ms,
            Match = [E || E <- Events, E#propagation_event.target_name =:= Name],
            {Propagated, Latency} = case Match of
                []  -> {false, undefined};
                Es  ->
                    Best = lists:min([E#propagation_event.latency_ms || E <- Es]),
                    {true, Best}
            end,
            WithinSla = Propagated andalso Latency =< Sla,
            #{target      => Name,
              sla_ms      => Sla,
              propagated  => Propagated,
              latency_ms  => Latency,
              within_sla  => WithinSla}
        end,
        Targets
    ),
    Fresh = lists:all(fun(M) -> maps:get(within_sla, M) end, PerTarget),
    {ok, #{entry_id => EntryId, fresh => Fresh, targets => PerTarget}}.
