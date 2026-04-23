%% @doc SLA tracking and escalation for exception queue items (TASK-052).
%%
%% SLA lifecycle:
%% 1. `set_sla/2` — attach a target resolution time to a queued item
%% 2. `check_overdue/0` — called periodically; returns items past their deadline
%% 3. `escalate/2` — raise an item's escalation tier and notify relevant staff
%%
%% Escalation tiers:
%%   0 = not escalated (default)
%%   1 = supervisor notified
%%   2 = manager notified
-module(cb_exception_sla).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    set_sla/2,
    check_overdue/0,
    escalate/2
]).

%%% --------------------------------------------------------------- API ----

%% @doc Attach an SLA to an exception item.
%%
%% `SlaMinutes` is the number of minutes from now by which the item must
%% be resolved.  Both `sla_minutes` and `sla_deadline` are stored on the
%% record.  Calling `set_sla/2` on an item that already has an SLA
%% overwrites the previous values.
-spec set_sla(uuid(), pos_integer()) ->
    {ok, #exception_item{}} | {error, not_found | term()}.
set_sla(ItemId, SlaMinutes) when is_integer(SlaMinutes), SlaMinutes > 0 ->
    Now = erlang:system_time(millisecond),
    Deadline = Now + SlaMinutes * 60 * 1000,
    F = fun() ->
        case mnesia:read(exception_item, ItemId, write) of
            [] ->
                {error, not_found};
            [Item] ->
                Updated = Item#exception_item{
                    sla_minutes  = SlaMinutes,
                    sla_deadline = Deadline,
                    updated_at   = Now
                },
                mnesia:write(exception_item, Updated, write),
                {ok, Updated}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result}       -> Result;
        {aborted, AbortReason} -> {error, AbortReason}
    end.

%% @doc Return all pending exception items that are past their SLA deadline.
%%
%% Items without a deadline (`sla_deadline = undefined`) are never returned.
-spec check_overdue() -> [#exception_item{}].
check_overdue() ->
    Now = erlang:system_time(millisecond),
    Pending = mnesia:dirty_index_read(exception_item, pending, status),
    [Item || Item <- Pending,
             Item#exception_item.sla_deadline =/= undefined,
             Item#exception_item.sla_deadline < Now].

%% @doc Escalate an exception item to the given tier.
%%
%% Tier 1 means a supervisor has been notified; tier 2 means a manager.
%% The item's status is changed to `escalated`.  Escalating an already-resolved
%% item returns `{error, already_resolved}`.
-spec escalate(uuid(), 1 | 2) ->
    {ok, #exception_item{}} | {error, not_found | already_resolved | term()}.
escalate(ItemId, Tier) when Tier =:= 1; Tier =:= 2 ->
    Now = erlang:system_time(millisecond),
    F = fun() ->
        case mnesia:read(exception_item, ItemId, write) of
            [] ->
                {error, not_found};
            [Item] when Item#exception_item.status =:= resolved ->
                {error, already_resolved};
            [Item] ->
                Updated = Item#exception_item{
                    status          = escalated,
                    escalation_tier = Tier,
                    updated_at      = Now
                },
                mnesia:write(exception_item, Updated, write),
                {ok, Updated}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result}       -> Result;
        {aborted, AbortReason} -> {error, AbortReason}
    end.
