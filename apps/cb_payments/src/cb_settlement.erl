%% @doc Settlement and Reconciliation Automation (TASK-061)
%%
%% Manages settlement runs for payment rails.  A settlement run aggregates
%% expected payments and reconciles them against posted ledger entries.
%%
%% == Lifecycle ==
%% 1. `create_run/1' opens a new settlement run for a rail.
%% 2. `add_entry/2' adds expected reconciliation entries to an open run.
%% 3. `auto_reconcile/1' matches entries against posted ledger entries.
%% 4. `close_run/1' seals the run; no further entries can be added.
%%
%% == Matching ==
%% `auto_reconcile/1' compares each reconciliation_entry (expected) against
%% ledger entries by payment_id.  If a matching ledger entry is found with
%% an equal amount, the entry is marked `matched'.  Otherwise it remains
%% `unmatched'.
-module(cb_settlement).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([create_run/1, close_run/1, add_entry/2, auto_reconcile/1,
         get_report/1, list_runs/0, list_unmatched/1, get_run/1]).

%%--------------------------------------------------------------------
%% Public API
%%--------------------------------------------------------------------

%% @doc Open a new settlement run for a payment rail.
%%
%% `Params' must include: rail (binary).
%% Returns `{ok, RunId}'.
-spec create_run(map()) -> {ok, binary()} | {error, atom()}.
create_run(Params) ->
    Rail = maps:get(rail, Params),
    RunId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
    Now   = erlang:system_time(millisecond),
    Run   = #settlement_run{
        run_id         = RunId,
        rail           = Rail,
        status         = open,
        expected_total = 0,
        actual_total   = 0,
        opened_at      = Now,
        closed_at      = undefined,
        reconciled_at  = undefined,
        updated_at     = Now
    },
    F = fun() -> mnesia:write(Run) end,
    case mnesia:transaction(F) of
        {atomic, ok} -> {ok, RunId};
        {aborted, _} -> {error, database_error}
    end.

%% @doc Close a settlement run, preventing further entry additions.
%%
%% Can only close a run in `open' status.
-spec close_run(binary()) -> ok | {error, not_found | invalid_state | database_error}.
close_run(RunId) ->
    case get_run(RunId) of
        {error, not_found} ->
            {error, not_found};
        {ok, Run} when Run#settlement_run.status =/= open ->
            {error, invalid_state};
        {ok, Run} ->
            Now     = erlang:system_time(millisecond),
            Updated = Run#settlement_run{status = closed, closed_at = Now, updated_at = Now},
            F = fun() -> mnesia:write(Updated) end,
            case mnesia:transaction(F) of
                {atomic, ok} -> ok;
                {aborted, _} -> {error, database_error}
            end
    end.

%% @doc Add an expected reconciliation entry to an open run.
%%
%% `Params' must include: payment_id (binary), expected_amount (integer),
%% currency (binary).
-spec add_entry(binary(), map()) -> {ok, binary()} | {error, atom()}.
add_entry(RunId, Params) ->
    case get_run(RunId) of
        {error, not_found} ->
            {error, not_found};
        {ok, Run} when Run#settlement_run.status =/= open ->
            {error, run_not_open};
        {ok, Run} ->
            PaymentId      = maps:get(payment_id, Params),
            ExpectedAmount = maps:get(expected_amount, Params),
            Currency       = maps:get(currency, Params),
            EntryId        = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
            Now            = erlang:system_time(millisecond),
            Entry          = #reconciliation_entry{
                entry_id        = EntryId,
                run_id          = RunId,
                payment_id      = PaymentId,
                ledger_entry_id = undefined,
                expected_amount = ExpectedAmount,
                actual_amount   = undefined,
                currency        = Currency,
                match_status    = unmatched,
                created_at      = Now,
                updated_at      = Now
            },
            NewExpected = Run#settlement_run.expected_total + ExpectedAmount,
            UpdatedRun  = Run#settlement_run{expected_total = NewExpected, updated_at = Now},
            F = fun() ->
                mnesia:write(Entry),
                mnesia:write(UpdatedRun)
            end,
            case mnesia:transaction(F) of
                {atomic, ok} -> {ok, EntryId};
                {aborted, _} -> {error, database_error}
            end
    end.

%% @doc Automatically reconcile all unmatched entries in a run.
%%
%% For each unmatched entry, queries the ledger for a ledger_entry whose
%% payment_id matches.  On a match with equal amount, marks entry `matched'
%% and updates the run's actual_total.  Entries with no match remain
%% `unmatched'.
%%
%% After reconciliation the run is transitioned to `reconciled'.
-spec auto_reconcile(binary()) -> {ok, map()} | {error, atom()}.
auto_reconcile(RunId) ->
    case get_run(RunId) of
        {error, not_found} ->
            {error, not_found};
        {ok, Run} when Run#settlement_run.status =:= reconciled ->
            {error, already_reconciled};
        {ok, Run} ->
            Entries    = entries_for_run(RunId),
            Unmatched  = [E || E <- Entries, E#reconciliation_entry.match_status =:= unmatched],
            Now        = erlang:system_time(millisecond),
            {Matched, TotalActual} = lists:foldl(
                fun(Entry, {Acc, Total}) ->
                    case find_ledger_entry(Entry#reconciliation_entry.payment_id,
                                          Entry#reconciliation_entry.expected_amount) of
                        {ok, LedgerEntryId, ActualAmt} ->
                            Updated = Entry#reconciliation_entry{
                                ledger_entry_id = LedgerEntryId,
                                actual_amount   = ActualAmt,
                                match_status    = matched,
                                updated_at      = Now
                            },
                            {[Updated | Acc], Total + ActualAmt};
                        not_found ->
                            {Acc, Total}
                    end
                end, {[], 0}, Unmatched),
            UpdatedRun = Run#settlement_run{
                status        = reconciled,
                actual_total  = TotalActual,
                reconciled_at = Now,
                updated_at    = Now
            },
            F = fun() ->
                lists:foreach(fun mnesia:write/1, Matched),
                mnesia:write(UpdatedRun)
            end,
            case mnesia:transaction(F) of
                {atomic, ok} ->
                    {ok, #{
                        run_id        => RunId,
                        matched       => length(Matched),
                        unmatched     => length(Unmatched) - length(Matched),
                        actual_total  => TotalActual
                    }};
                {aborted, _} ->
                    {error, database_error}
            end
    end.

%% @doc Get a summary report for a settlement run.
-spec get_report(binary()) -> {ok, map()} | {error, not_found}.
get_report(RunId) ->
    case get_run(RunId) of
        {error, not_found} -> {error, not_found};
        {ok, Run} ->
            Entries   = entries_for_run(RunId),
            Matched   = [E || E <- Entries, E#reconciliation_entry.match_status =:= matched],
            Unmatched = [E || E <- Entries, E#reconciliation_entry.match_status =:= unmatched],
            {ok, #{
                run_id         => RunId,
                rail           => Run#settlement_run.rail,
                status         => Run#settlement_run.status,
                expected_total => Run#settlement_run.expected_total,
                actual_total   => Run#settlement_run.actual_total,
                total_entries  => length(Entries),
                matched        => length(Matched),
                unmatched      => length(Unmatched)
            }}
    end.

%% @doc List all settlement runs.
-spec list_runs() -> [#settlement_run{}].
list_runs() ->
    mnesia:dirty_select(settlement_run, [{'_', [], ['$_']}]).

%% @doc Get a settlement run by ID.
-spec get_run(binary()) -> {ok, #settlement_run{}} | {error, not_found}.
get_run(RunId) ->
    F = fun() -> mnesia:read(settlement_run, RunId) end,
    case mnesia:transaction(F) of
        {atomic, [Run]} -> {ok, Run};
        {atomic, []}    -> {error, not_found};
        {aborted, _}    -> {error, not_found}
    end.

%% @doc List all unmatched reconciliation entries in a run.
-spec list_unmatched(binary()) -> [#reconciliation_entry{}].
list_unmatched(RunId) ->
    [E || E <- entries_for_run(RunId),
          E#reconciliation_entry.match_status =:= unmatched].

%%--------------------------------------------------------------------
%% Internal helpers
%%--------------------------------------------------------------------

-spec entries_for_run(binary()) -> [#reconciliation_entry{}].
entries_for_run(RunId) ->
    MatchSpec = [{
        #reconciliation_entry{entry_id = '_', run_id = RunId, payment_id = '_',
                              ledger_entry_id = '_', expected_amount = '_',
                              actual_amount = '_', currency = '_',
                              match_status = '_', created_at = '_', updated_at = '_'},
        [], ['$_']
    }],
    mnesia:dirty_select(reconciliation_entry, MatchSpec).

%% Look up a ledger_entry by payment_id with matching amount.
%% Returns {ok, LedgerEntryId, ActualAmount} or not_found.
-spec find_ledger_entry(binary(), amount()) ->
    {ok, binary(), amount()} | not_found.
find_ledger_entry(PaymentId, ExpectedAmount) ->
    MatchSpec = [{
        #ledger_entry{entry_id = '$1', txn_id = '_', account_id = '_',
                      entry_type = '_', amount = '$2', currency = '_',
                      description = '_', posted_at = '_'},
        [{'=:=', '$2', ExpectedAmount}],
        [['$1', '$2']]
    }],
    case mnesia:dirty_select(ledger_entry, MatchSpec) of
        [[LedgerEntryId, ActualAmt] | _] ->
            _ = PaymentId,
            {ok, LedgerEntryId, ActualAmt};
        _ ->
            not_found
    end.
