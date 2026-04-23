% =============================================================================
% @doc IronLedger - Double-Entry Bookkeeping Core
% =============================================================================
%%
%% This module implements the core double-entry ledger functionality for
%% IronLedger. It provides the fundamental operations for recording financial
%% transactions as pairs of debit and credit entries.
%%
%% == Double-Entry Bookkeeping ==
%%
%% This module enforces the fundamental principles of double-entry bookkeeping:
%%
%% 1. **Every transaction has equal debits and credits**
%%    For every amount debited to one account, an equal amount must be credited
%%    to another account. This maintains the accounting equation:
%%
%%    ```
%%    Assets = Liabilities + Equity
%%    ```
%%
%% 2. **Entries are immutable**
%%    Once a ledger entry is posted, it can never be modified or deleted.
%%    Corrections are made by posting new entries (reversals or adjustments).
%%    This creates a complete, tamper-proof audit trail.
%%
%% 3. **Trial Balance Validation**
%%    The sum of all debits must always equal the sum of all credits across
%%    the entire ledger. The `post_entries/2` function enforces this invariant.
%%
%% == Usage ==
%%
%% To post a transfer of $100 from Account A to Account B:
%%
%% ```erlang
%% DebitEntry = #ledger_entry{
%%     entry_id = uuid:gen_v4(),
%%     txn_id = TxnId,
%%     account_id = AccountAId,
%%     entry_type = debit,
%%     amount = 10000,  % $100.00 in cents
%%     currency = <<"USD">>,
%%     description = <<"Transfer to Account B">>,
%%     posted_at = erlang:system_time(millisecond)
%% },
%% CreditEntry = #ledger_entry{
%%     entry_id = uuid:gen_v4(),
%%     txn_id = TxnId,
%%     account_id = AccountBId,
%%     entry_type = credit,
%%     amount = 10000,
%%     currency = <<"USD">>,
%%     description = <<"Transfer from Account A">>,
%%     posted_at = erlang:system_time(millisecond)
%% },
%% mnesia:transaction(fun() -> cb_ledger:post_entries(DebitEntry, CreditEntry) end).
%% ```
%%
%% == Error Handling ==
%%
%% All functions return `{ok, Value}` on success or `{error, Reason}` on failure.
%% Valid error reasons include:
%% - `currency_mismatch`: Debit and credit entries use different currencies
%% - `invalid_entry_types`: Entry types are not properly specified (not debit/credit pair)
%% - `ledger_imbalance`: Debit and credit amounts do not match
%% - `zero_amount`: Cannot post an entry with zero amount
%%
%% @end
% =============================================================================

-module(cb_ledger).

-include("cb_ledger.hrl").

-export([
    post_entries/2,
    get_entries_for_transaction/1,
    get_entries_for_account/3,
    get_latest_entries/1,
    get_general_ledger_entries/4,
    create_chart_account/4,
    get_chart_accounts/0,
    get_chart_account/1,
    get_trial_balance/1,
    create_balance_snapshot/1,
    get_balance_snapshots/3
]).

%% @doc Posts a debit/credit entry pair atomically to the ledger.
%%
%% This function implements the core double-entry bookkeeping operation by
%% validating and writing a pair of ledger entries (one debit, one credit).
%% It must be called from within an existing `mnesia:transaction/1` context.
%%
%% == Validation Rules ==
%%
%% 1. **Entry Type Validation**: First entry must be `debit`, second must be `credit`
%% 2. **Amount Matching**: Debit and credit amounts must be exactly equal
%% 3. **Currency Matching**: Both entries must use the same currency
%% 4. **Positive Amount**: Amount must be greater than zero
%%
%% == Parameters ==
%%
%% - `DebitEntry`: The debit side of the transaction (money flowing OUT)
%% - `CreditEntry`: The credit side of the transaction (money flowing IN)
%%
%% == Returns ==
%%
%% - `ok`: Both entries were successfully written to the ledger
%% - `{error, currency_mismatch}`: Entries use different currencies
%% - `{error, invalid_entry_types}`: Entry types are not properly debit/credit
%% - `{error, ledger_imbalance}`: Debit and credit amounts don't match
%% - `{error, zero_amount}`: Amount is zero or negative
%%
%% == Example ==
%%
%% ```erlang
%% mnesia:transaction(fun() ->
%%     cb_ledger:post_entries(DebitEntry, CreditEntry)
%% end).
%% ```
%%
%% @see ledger_entry
%% @see entry_type
-spec post_entries(#ledger_entry{}, #ledger_entry{}) -> ok | {error, currency_mismatch | invalid_entry_types | ledger_imbalance | zero_amount}.
post_entries(DebitEntry, CreditEntry) ->
    %% Validate entry types
    case {DebitEntry#ledger_entry.entry_type, CreditEntry#ledger_entry.entry_type} of
        {debit, credit} ->
            %% Validate amounts match
            case DebitEntry#ledger_entry.amount =:= CreditEntry#ledger_entry.amount of
                true ->
                    %% Validate currency matches
                    case DebitEntry#ledger_entry.currency =:= CreditEntry#ledger_entry.currency of
                        true ->
                            %% Validate positive amount
                            case DebitEntry#ledger_entry.amount > 0 of
                                true ->
                                    mnesia:write(DebitEntry),
                                    mnesia:write(CreditEntry),
                                    ok;
                                false ->
                                    {error, zero_amount}
                            end;
                        false ->
                            {error, currency_mismatch}
                    end;
                false ->
                    {error, ledger_imbalance}
            end;
        _ ->
            {error, invalid_entry_types}
    end.

%% @doc Retrieves all ledger entries associated with a specific transaction.
%%
%% In double-entry bookkeeping, every transaction creates one or more ledger
%% entries. For a simple transfer, there will be exactly two entries:
%% one debit and one credit. This function allows audit and reconciliation
%% by fetching all entries for a given transaction ID.
%%
%% == Use Cases ==
%%
%% - Audit: Review all entries created by a specific transaction
%% - Reconciliation: Verify debit/credit balance for a transaction
%% - Error Investigation: Find all affected accounts for a failed transaction
%%
%% == Parameters ==
%%
%% - `TxnId`: The UUID of the transaction to look up
%%
%% == Returns ==
%%
%% - `{ok, [LedgerEntry]}`: List of all ledger entries for the transaction
%% - `{error, Reason}`: If the Mnesia transaction fails
%%
%% @see transaction
%% @see ledger_entry
-spec get_entries_for_transaction(uuid()) -> {ok, [#ledger_entry{}]} | {error, atom()}.
get_entries_for_transaction(TxnId) ->
    F = fun() ->
        mnesia:index_read(ledger_entry, TxnId, txn_id)
    end,
    case mnesia:transaction(F) of
        {atomic, Entries} -> {ok, Entries};
        {aborted, Reason} -> {error, Reason}
    end.

%% @doc Retrieves paginated ledger entries for a specific account.
%%
%% This function provides historical transaction data for an account, supporting
%% both account statement generation and audit review. Results are sorted by
%% posting date (most recent first) and paginated for efficient retrieval.
%%
%% == Use Cases ==
%%
%% - Account Statements: Generate periodic statements for customers
%% - Audit Trail: Review all transactions affecting an account
%% - Reconciliation: Match entries against external records
%% - Account History: View long-running account activity
%%
%% == Pagination ==
%%
%% Results are returned in pages with the following structure:
%% ```erlang
%% #{
%%     items => [LedgerEntry, ...],    % List of entries for this page
%%     total => non_neg_integer(),     % Total entries for this account
%%     page => pos_integer(),          % Current page number (1-indexed)
%%     page_size => pos_integer()      % Entries per page
%% }
%% ```
%%
%% == Parameters ==
%%
%% - `AccountId`: UUID of the account to query
%% - `Page`: Page number (1-indexed, must be >= 1)
%% - `PageSize`: Number of entries per page (must be 1-100)
%%
%% == Returns ==
%%
%% - `{ok, ResultMap}`: Paginated results as shown above
%% - `{error, invalid_pagination}`: If Page < 1 or PageSize not in 1-100
%% - `{error, Reason}`: If the Mnesia transaction fails
%%
%% @see ledger_entry
%% @see account
-spec get_entries_for_account(uuid(), pos_integer(), pos_integer()) ->
    {ok, #{items => [#ledger_entry{}], total => non_neg_integer(), page => pos_integer(), page_size => pos_integer()}} |
    {error, atom()}.
get_entries_for_account(AccountId, Page, PageSize) when Page >= 1, PageSize >= 1, PageSize =< 100 ->
    F = fun() ->
        Entries = mnesia:index_read(ledger_entry, AccountId, account_id),
        %% Sort by posted_at descending
        Sorted = lists:sort(
            fun(A, B) -> A#ledger_entry.posted_at >= B#ledger_entry.posted_at end,
            Entries
        ),
        Total = length(Sorted),
        Offset = (Page - 1) * PageSize,
        Items = lists:sublist(Sorted, Offset + 1, PageSize),
        #{items => Items, total => Total, page => Page, page_size => PageSize}
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> {ok, Result};
        {aborted, Reason} -> {error, Reason}
    end;
get_entries_for_account(_, _, _) ->
    {error, invalid_pagination}.

%% @doc Returns the N most recently posted ledger entries across all accounts.
-spec get_latest_entries(pos_integer()) -> {ok, [#ledger_entry{}]} | {error, atom()}.
get_latest_entries(Limit) when is_integer(Limit), Limit >= 1, Limit =< 500 ->
    F = fun() ->
        All = mnesia:foldl(fun(Entry, Acc) -> [Entry | Acc] end, [], ledger_entry),
        Sorted = lists:sort(
            fun(A, B) -> A#ledger_entry.posted_at >= B#ledger_entry.posted_at end,
            All
        ),
        lists:sublist(Sorted, Limit)
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> {ok, Result};
        {aborted, Reason} -> {error, Reason}
    end;
get_latest_entries(_) ->
    {error, invalid_limit}.

%% @doc Returns paginated ledger entries across all accounts with optional filters.
%%
%% Filters is a map that may contain any of:
%% - `account_id' (binary): restrict to entries for one account
%% - `entry_type' (debit | credit): restrict to one direction
%% - `currency' (currency()): restrict by currency
%% - `from_ms' (integer): lower bound on posted_at (inclusive)
%% - `to_ms' (integer): upper bound on posted_at (inclusive)
%%
%% Results are sorted newest-first and paginated.
-spec get_general_ledger_entries(map(), pos_integer(), pos_integer(), pos_integer()) ->
    {ok, #{items => [#ledger_entry{}], total => non_neg_integer(),
           page => pos_integer(), page_size => pos_integer()}} |
    {error, atom()}.
get_general_ledger_entries(Filters, Page, PageSize, _MaxLimit)
        when Page >= 1, PageSize >= 1, PageSize =< 100 ->
    F = fun() ->
        All = case maps:get(account_id, Filters, undefined) of
            undefined ->
                mnesia:foldl(fun(E, Acc) -> [E | Acc] end, [], ledger_entry);
            AccId ->
                mnesia:index_read(ledger_entry, AccId, account_id)
        end,
        Filtered = lists:filter(
            fun(E) -> matches_gl_filters(E, Filters) end,
            All
        ),
        Sorted = lists:sort(
            fun(A, B) -> A#ledger_entry.posted_at >= B#ledger_entry.posted_at end,
            Filtered
        ),
        Total = length(Sorted),
        Offset = (Page - 1) * PageSize,
        Items = lists:sublist(Sorted, Offset + 1, PageSize),
        #{items => Items, total => Total, page => Page, page_size => PageSize}
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> {ok, Result};
        {aborted, Reason} -> {error, Reason}
    end;
get_general_ledger_entries(_, _, _, _) ->
    {error, invalid_pagination}.

%% @private Apply per-entry filter predicates for general ledger queries.
-spec matches_gl_filters(#ledger_entry{}, map()) -> boolean().
matches_gl_filters(E, Filters) ->
    EntryTypeOk = case maps:get(entry_type, Filters, undefined) of
        undefined -> true;
        ET -> E#ledger_entry.entry_type =:= ET
    end,
    CurrencyOk = case maps:get(currency, Filters, undefined) of
        undefined -> true;
        C -> E#ledger_entry.currency =:= C
    end,
    FromOk = case maps:get(from_ms, Filters, undefined) of
        undefined -> true;
        From -> E#ledger_entry.posted_at >= From
    end,
    ToOk = case maps:get(to_ms, Filters, undefined) of
        undefined -> true;
        To -> E#ledger_entry.posted_at =< To
    end,
    EntryTypeOk andalso CurrencyOk andalso FromOk andalso ToOk.

%% @doc Lists all active chart-of-accounts nodes, sorted by code.
-spec get_chart_accounts() -> {ok, [#chart_account{}]} | {error, atom()}.
get_chart_accounts() ->
    F = fun() ->
        mnesia:foldl(fun(A, Acc) -> [A | Acc] end, [], chart_account)
    end,
    case mnesia:transaction(F) of
        {atomic, Accounts} ->
            Sorted = lists:sort(
                fun(A, B) -> A#chart_account.code =< B#chart_account.code end,
                Accounts
            ),
            {ok, Sorted};
        {aborted, Reason} -> {error, Reason}
    end.

%% @doc Retrieves a single chart-of-accounts node by its code.
-spec get_chart_account(binary()) -> {ok, #chart_account{}} | {error, atom()}.
get_chart_account(Code) ->
    F = fun() ->
        mnesia:read(chart_account, Code)
    end,
    case mnesia:transaction(F) of
        {atomic, [Account]} -> {ok, Account};
        {atomic, []} -> {error, chart_account_not_found};
        {aborted, Reason} -> {error, Reason}
    end.

%% @doc Creates a chart-of-accounts node.
-spec create_chart_account(binary(), binary(), gl_account_type(), binary() | undefined) ->
    {ok, #chart_account{}} | {error, atom()}.
create_chart_account(Code, Name, AccountType, ParentCode)
        when is_binary(Code), is_binary(Name) ->
    case lists:member(AccountType, [asset, liability, equity, revenue, expense]) of
        true ->
            F = fun() ->
                case mnesia:read(chart_account, Code) of
                    [_] ->
                        {error, chart_account_exists};
                    [] ->
                        case validate_parent_chart_account(ParentCode) of
                            ok ->
                                Now = erlang:system_time(millisecond),
                                Account = #chart_account{
                                    code = Code,
                                    name = Name,
                                    account_type = AccountType,
                                    parent_code = ParentCode,
                                    status = active,
                                    created_at = Now,
                                    updated_at = Now
                                },
                                mnesia:write(Account),
                                {ok, Account};
                            {error, _} = Error ->
                                Error
                        end
                end
            end,
            case mnesia:transaction(F) of
                {atomic, Result} -> Result;
                {aborted, _Reason} -> {error, database_error}
            end;
        false ->
            {error, invalid_account_type}
    end.

%% @doc Returns trial balance totals for the requested currency.
-spec get_trial_balance(currency()) -> {ok, map()} | {error, atom()}.
get_trial_balance(Currency) ->
    F = fun() ->
        Entries = mnesia:index_read(ledger_entry, Currency, currency),
        {DebitTotal, CreditTotal} = lists:foldl(
            fun(Entry, {Debits, Credits}) ->
                case Entry#ledger_entry.entry_type of
                    debit -> {Debits + Entry#ledger_entry.amount, Credits};
                    credit -> {Debits, Credits + Entry#ledger_entry.amount}
                end
            end,
            {0, 0},
            Entries
        ),
        #{
            currency => Currency,
            total_debits => DebitTotal,
            total_credits => CreditTotal,
            balanced => DebitTotal =:= CreditTotal,
            as_of => erlang:system_time(millisecond)
        }
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> {ok, Result};
        {aborted, Reason} -> {error, Reason}
    end.

%% @doc Captures a point-in-time account balance snapshot.
-spec create_balance_snapshot(uuid()) -> {ok, #balance_snapshot{}} | {error, atom()}.
create_balance_snapshot(AccountId) ->
    F = fun() ->
        case mnesia:read(account, AccountId) of
            [Account] ->
                Snapshot = #balance_snapshot{
                    snapshot_id = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
                    account_id = AccountId,
                    balance = Account#account.balance,
                    currency = Account#account.currency,
                    snapshot_at = erlang:system_time(millisecond)
                },
                mnesia:write(Snapshot),
                {ok, Snapshot};
            [] ->
                {error, account_not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

%% @doc Retrieves paginated snapshots for an account, newest first.
-spec get_balance_snapshots(uuid(), pos_integer(), pos_integer()) -> {ok, map()} | {error, atom()}.
get_balance_snapshots(AccountId, Page, PageSize)
        when Page >= 1, PageSize >= 1, PageSize =< 100 ->
    F = fun() ->
        Snapshots = mnesia:index_read(balance_snapshot, AccountId, account_id),
        Sorted = lists:sort(
            fun(A, B) -> A#balance_snapshot.snapshot_at >= B#balance_snapshot.snapshot_at end,
            Snapshots
        ),
        Total = length(Sorted),
        Offset = (Page - 1) * PageSize,
        Items = lists:sublist(Sorted, Offset + 1, PageSize),
        #{items => Items, total => Total, page => Page, page_size => PageSize}
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> {ok, Result};
        {aborted, _Reason} -> {error, database_error}
    end;
get_balance_snapshots(_, _, _) ->
    {error, invalid_pagination}.

-spec validate_parent_chart_account(binary() | undefined) -> ok | {error, parent_chart_account_not_found}.
validate_parent_chart_account(undefined) ->
    ok;
validate_parent_chart_account(ParentCode) when is_binary(ParentCode) ->
    case mnesia:read(chart_account, ParentCode) of
        [_] -> ok;
        [] -> {error, parent_chart_account_not_found}
    end;
validate_parent_chart_account(_) ->
    {error, parent_chart_account_not_found}.
