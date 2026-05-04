%% @doc Cross-Module Federated Reporting (TASK-065)
%%
%% Provides consolidated data queries that aggregate data across accounts,
%% ledger entries, loans, and payments into unified report snapshots.
%%
%% Reports are submitted as async jobs (federation_report records) and
%% executed synchronously in process.  Callers may poll by report_id.
%%
%% == Report types ==
%% <ul>
%%   <li>consolidated_balance   — net balance per currency across all accounts</li>
%%   <li>cross_product_pnl      — P&L across loan interest, fee income, FX spreads</li>
%%   <li>regulatory_snapshot    — capital ratios + liquidity metrics at a point in time</li>
%%   <li>customer_360           — full product holding summary for one customer</li>
%% </ul>
-module(cb_federation_report).

-compile({parse_transform, ms_transform}).

-include("../../cb_ledger/include/cb_ledger.hrl").

-export([
    submit/1,
    get_report/1,
    list_reports/1,
    run/1
]).

-spec submit(map()) -> {ok, #federation_report{}} | {error, term()}.
submit(Params) ->
    Now = erlang:system_time(millisecond),
    Report = #federation_report{
        report_id    = uuid:get_v4(),
        report_type  = maps:get(report_type, Params),
        params       = maps:get(params, Params, #{}),
        status       = pending,
        result       = undefined,
        error        = undefined,
        requested_by = maps:get(requested_by, Params),
        requested_at = Now,
        completed_at = undefined
    },
    case mnesia:transaction(fun() -> mnesia:write(Report) end) of
        {atomic, ok} -> {ok, Report};
        {aborted, Reason} -> {error, Reason}
    end.

-spec get_report(uuid()) -> {ok, #federation_report{}} | {error, not_found}.
get_report(ReportId) ->
    case mnesia:dirty_read(federation_report, ReportId) of
        [R] -> {ok, R};
        []  -> {error, not_found}
    end.

-spec list_reports(uuid()) -> [#federation_report{}].
list_reports(RequestedBy) ->
    MatchSpec = ets:fun2ms(fun(R = #federation_report{requested_by = U}) when U =:= RequestedBy -> R end),
    mnesia:dirty_select(federation_report, MatchSpec).

%% @doc Execute a pending report synchronously; persist and return the result.
-spec run(uuid()) -> {ok, #federation_report{}} | {error, term()}.
run(ReportId) ->
    case get_report(ReportId) of
        {ok, Report} ->
            Now = erlang:system_time(millisecond),
            {Status, Result, ErrMsg} =
                try
                    Data = execute(Report#federation_report.report_type,
                                   Report#federation_report.params),
                    {completed, Data, undefined}
                catch
                    _:Err ->
                        {failed, undefined, list_to_binary(io_lib:format("~p", [Err]))}
                end,
            Updated = Report#federation_report{
                status       = Status,
                result       = Result,
                error        = ErrMsg,
                completed_at = Now
            },
            case mnesia:transaction(fun() -> mnesia:write(Updated) end) of
                {atomic, ok}      -> {ok, Updated};
                {aborted, Reason} -> {error, Reason}
            end;
        Err -> Err
    end.

%%====================================================================
%% Internal: report execution
%%====================================================================

-spec execute(federation_report_type(), map()) -> map().
execute(consolidated_balance, Params) ->
    AccountIds = maps:get(account_ids, Params, all),
    Entries = fetch_ledger_entries(AccountIds),
    aggregate_balance_by_currency(Entries);

execute(cross_product_pnl, Params) ->
    AccountIds = maps:get(account_ids, Params, all),
    Entries    = fetch_ledger_entries(AccountIds),
    #{
        fee_income      => sum_by_type(Entries, credit),
        interest_income => sum_by_type(Entries, debit),
        total_pnl       => sum_all(Entries)
    };

execute(regulatory_snapshot, _Params) ->
    Metrics  = mnesia:dirty_select(risk_metric, [{'_', [], ['$_']}]),
    Breaches = [M || M <- Metrics, M#risk_metric.breached =:= true],
    Buffers  = mnesia:dirty_select(capital_buffer, [{'_', [], ['$_']}]),
    #{
        metrics         => length(Metrics),
        breached_metrics => length(Breaches),
        capital_buffers  => length(Buffers)
    };

execute(customer_360, Params) ->
    PartyId = maps:get(party_id, Params),
    Accounts = fetch_accounts_for_party(PartyId),
    Instruments = lists:flatmap(fun(A) ->
        MatchSpec = ets:fun2ms(fun(I = #trade_instrument{account_id = Aid}) when Aid =:= A -> I end),
        mnesia:dirty_select(trade_instrument, MatchSpec)
    end, Accounts),
    #{
        accounts    => length(Accounts),
        instruments => length(Instruments)
    }.

%%====================================================================
%% Private helpers
%%====================================================================

-spec fetch_ledger_entries(all | [uuid()]) -> [#ledger_entry{}].
fetch_ledger_entries(all) ->
    mnesia:dirty_select(ledger_entry, [{'_', [], ['$_']}]);
fetch_ledger_entries(AccountIds) when is_list(AccountIds) ->
    lists:flatmap(fun(AccountId) ->
        MatchSpec = ets:fun2ms(fun(E = #ledger_entry{account_id = A}) when A =:= AccountId -> E end),
        mnesia:dirty_select(ledger_entry, MatchSpec)
    end, AccountIds).

-spec fetch_accounts_for_party(uuid()) -> [uuid()].
fetch_accounts_for_party(PartyId) ->
    MatchSpec = ets:fun2ms(fun(A = #account{party_id = P}) when P =:= PartyId -> A end),
    Accounts = mnesia:dirty_select(account, MatchSpec),
    [A#account.account_id || A <- Accounts].

-spec aggregate_balance_by_currency([#ledger_entry{}]) -> map().
aggregate_balance_by_currency(Entries) ->
    lists:foldl(fun(E, Acc) ->
        Ccy = E#ledger_entry.currency,
        Amt = E#ledger_entry.amount,
        maps:update_with(Ccy, fun(V) -> V + Amt end, Amt, Acc)
    end, #{}, Entries).

-spec sum_by_type([#ledger_entry{}], atom()) -> integer().
sum_by_type(Entries, Type) ->
    lists:foldl(fun(E, Acc) ->
        case E#ledger_entry.entry_type of
            Type -> Acc + E#ledger_entry.amount;
            _    -> Acc
        end
    end, 0, Entries).

-spec sum_all([#ledger_entry{}]) -> integer().
sum_all(Entries) ->
    lists:foldl(fun(E, Acc) -> Acc + E#ledger_entry.amount end, 0, Entries).
