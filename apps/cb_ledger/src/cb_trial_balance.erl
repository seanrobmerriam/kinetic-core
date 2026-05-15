%% @doc Trial Balance Generator
%%
%% Produces a point-in-time trial balance showing every chart-of-accounts
%% entry with its debit and credit balance in minor units.
%%
%% Unlike `cb_ledger:get_trial_balance/1` which returns only aggregate
%% totals, this module returns a per-account breakdown suitable for
%% financial statement presentation.
%%
%% == Usage ==
%%
%% ```
%% cb_trial_balance:generate(<<"USD">>).
%% cb_trial_balance:generate(<<"USD">>, {date, {2025, 3, 31}}).
%% ```
-module(cb_trial_balance).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    generate/1,
    generate/2
]).

-type options() :: #{
    currency => currency(),
    as_of_date => calendar:date()
}.

-type account_balance() :: #{
    account_id := uuid(),
    account_name := binary(),
    currency := currency(),
    debit_balance_minor := amount(),
    credit_balance_minor := amount()
}.

-type result() :: #{
    accounts := [account_balance()],
    generated_at := timestamp_ms()
}.

%% @doc Generates trial balance for all accounts in the given currency.
%% Accounts with zero debit and zero credit are still included.
-spec generate(currency()) -> {ok, result()} | {error, atom()}.
generate(Currency) ->
    generate(Currency, #{}).

%% @doc Generates trial balance with additional options.
%%
%% Options:
%%   - currency:Override the top-level currency (defaults to the argument)
%%   - as_of_date: Restrict to ledger entries posted before this date
%%                 (default: current system date)
-spec generate(currency(), options()) -> {ok, result()} | {error, atom()}.
generate(Currency, Opts) ->
    AsOf = case maps:get(as_of_date, Opts, undefined) of
        undefined -> os:system_time(second);
        Date when is_tuple(Date) -> calendar:date_to_gregorian_seconds(Date) * 1000
    end,
    F = fun() ->
        %% Build a map: account_id -> #{debit_balance_minor, credit_balance_minor}
        Accounts = cb_ledger:get_chart_accounts(),
        AccountMap = build_account_map(Accounts),
        %% Scan all ledger entries for this currency, up to AsOf timestamp
        Entries = mnesia:foldl(
            fun(Entry, Acc) ->
                case Entry#ledger_entry.currency =:= Currency
                     andalso Entry#ledger_entry.posted_at =< AsOf of
                    true -> [Entry | Acc];
                    false -> Acc
                end
            end,
            [],
            ledger_entry
        ),
        %% Aggregate by account
        BalanceMap = lists:foldl(
            fun(Entry, BM) ->
                AccId = Entry#ledger_entry.account_id,
                case Entry#ledger_entry.entry_type of
                    debit ->
                        update_debit(AccId, Entry#ledger_entry.amount, BM);
                    credit ->
                        update_credit(AccId, Entry#ledger_entry.amount, BM)
                end
            end,
            AccountMap,
            Entries
        ),
        %% Build result with account names from chart_of_accounts
        ChartAccounts = cb_ledger:get_chart_accounts(),
        ChartMap = maps:from_list([
            {CA#chart_account.code, CA#chart_account.name}
         || CA <- ChartAccounts
        ]),
        Accounts2 = [
            begin
                Name = maps:get(AccId, ChartMap, <<"Unknown">>),
                #{
                    account_id => AccId,
                    account_name => Name,
                    currency => Currency,
                    debit_balance_minor => maps:get(debit, Bal, 0),
                    credit_balance_minor => maps:get(credit, Bal, 0)
                }
            end
         || {AccId, Bal} <- maps:to_list(BalanceMap)
        ],
        #{
            accounts => Accounts2,
            generated_at => erlang:system_time(millisecond)
        }
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> {ok, Result};
        {aborted, Reason} -> {error, Reason}
    end.

%% @private
build_account_map({ok, ChartAccounts}) ->
    maps:from_list([
        {CA#chart_account.code, #{debit => 0, credit => 0}}
     || CA <- ChartAccounts
    ]);
build_account_map(Accounts) when is_list(Accounts) ->
    maps:from_list([
        {CA#chart_account.code, #{debit => 0, credit => 0}}
     || CA <- Accounts
    ]).

update_debit(AccId, Amount, BalanceMap) ->
    case maps:find(AccId, BalanceMap) of
        {ok, Bal} ->
            BalanceMap#{AccId := Bal#{debit => maps:get(debit, Bal, 0) + Amount}};
        error ->
            BalanceMap#{AccId => #{debit => Amount, credit => 0}}
    end.

update_credit(AccId, Amount, BalanceMap) ->
    case maps:find(AccId, BalanceMap) of
        {ok, Bal} ->
            BalanceMap#{AccId := Bal#{credit => maps:get(credit, Bal, 0) + Amount}};
        error ->
            BalanceMap#{AccId => #{debit => 0, credit => Amount}}
    end.