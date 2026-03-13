-module(cb_ledger).

-include("cb_ledger.hrl").

-export([
    post_entries/2,
    get_entries_for_transaction/1,
    get_entries_for_account/3
]).

%% @doc Post a debit/credit pair atomically inside a Mnesia transaction.
%% This function must be called from within an existing mnesia:transaction/1.
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

%% @doc Get all ledger entries for a transaction.
-spec get_entries_for_transaction(uuid()) -> {ok, [#ledger_entry{}]} | {error, atom()}.
get_entries_for_transaction(TxnId) ->
    F = fun() ->
        mnesia:index_read(ledger_entry, TxnId, txn_id)
    end,
    case mnesia:transaction(F) of
        {atomic, Entries} -> {ok, Entries};
        {aborted, Reason} -> {error, Reason}
    end.

%% @doc Get paginated ledger entries for an account.
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
