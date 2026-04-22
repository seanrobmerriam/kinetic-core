-module(cb_ledger_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    post_entries_ok/1,
    post_entries_amount_mismatch/1,
    post_entries_currency_mismatch/1,
    post_entries_zero_amount/1,
    get_entries_for_transaction_ok/1,
    get_entries_for_account_ok/1,
    create_chart_account_ok/1,
    trial_balance_ok/1,
    balance_snapshot_ok/1
]).

all() ->
    [
        post_entries_ok,
        post_entries_amount_mismatch,
        post_entries_currency_mismatch,
        post_entries_zero_amount,
        get_entries_for_transaction_ok,
        get_entries_for_account_ok,
        create_chart_account_ok,
        trial_balance_ok,
        balance_snapshot_ok
    ].

init_per_suite(Config) ->
    mnesia:start(),
    cb_schema:create_tables(),
    Config.

end_per_suite(_Config) ->
    mnesia:stop(),
    mnesia:delete_schema([node()]),
    ok.

init_per_testcase(_TestCase, Config) ->
    lists:foreach(fun(T) -> mnesia:clear_table(T) end,
                  [party, account, transaction, ledger_entry, chart_account, balance_snapshot]),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

%% Test: Post valid debit/credit entries
post_entries_ok(_Config) ->
    Now = erlang:system_time(millisecond),
    TxnId = <<"txn-1">>,
    
    DebitEntry = #ledger_entry{
        entry_id = <<"entry-debit-1">>,
        txn_id = TxnId,
        account_id = <<"account-1">>,
        entry_type = debit,
        amount = 1000,
        currency = 'USD',
        description = <<"Test debit">>,
        posted_at = Now
    },
    
    CreditEntry = #ledger_entry{
        entry_id = <<"entry-credit-1">>,
        txn_id = TxnId,
        account_id = <<"account-2">>,
        entry_type = credit,
        amount = 1000,
        currency = 'USD',
        description = <<"Test credit">>,
        posted_at = Now
    },
    
    F = fun() ->
        cb_ledger:post_entries(DebitEntry, CreditEntry)
    end,
    {atomic, ok} = mnesia:transaction(F),
    
    %% Verify entries were written
    {ok, Entries} = cb_ledger:get_entries_for_transaction(TxnId),
    ?assertEqual(2, length(Entries)),
    ok.

%% Test: Post entries with mismatched amounts
post_entries_amount_mismatch(_Config) ->
    Now = erlang:system_time(millisecond),
    TxnId = <<"txn-2">>,
    
    DebitEntry = #ledger_entry{
        entry_id = <<"entry-debit-2">>,
        txn_id = TxnId,
        account_id = <<"account-1">>,
        entry_type = debit,
        amount = 1000,
        currency = 'USD',
        description = <<"Test debit">>,
        posted_at = Now
    },
    
    CreditEntry = #ledger_entry{
        entry_id = <<"entry-credit-2">>,
        txn_id = TxnId,
        account_id = <<"account-2">>,
        entry_type = credit,
        amount = 500,  %% Different amount!
        currency = 'USD',
        description = <<"Test credit">>,
        posted_at = Now
    },
    
    F = fun() ->
        cb_ledger:post_entries(DebitEntry, CreditEntry)
    end,
    {atomic, {error, ledger_imbalance}} = mnesia:transaction(F),
    ok.

%% Test: Post entries with mismatched currencies
post_entries_currency_mismatch(_Config) ->
    Now = erlang:system_time(millisecond),
    TxnId = <<"txn-3">>,
    
    DebitEntry = #ledger_entry{
        entry_id = <<"entry-debit-3">>,
        txn_id = TxnId,
        account_id = <<"account-1">>,
        entry_type = debit,
        amount = 1000,
        currency = 'USD',
        description = <<"Test debit">>,
        posted_at = Now
    },
    
    CreditEntry = #ledger_entry{
        entry_id = <<"entry-credit-3">>,
        txn_id = TxnId,
        account_id = <<"account-2">>,
        entry_type = credit,
        amount = 1000,
        currency = 'EUR',  %% Different currency!
        description = <<"Test credit">>,
        posted_at = Now
    },
    
    F = fun() ->
        cb_ledger:post_entries(DebitEntry, CreditEntry)
    end,
    {atomic, {error, currency_mismatch}} = mnesia:transaction(F),
    ok.

%% Test: Post entries with zero amount
post_entries_zero_amount(_Config) ->
    Now = erlang:system_time(millisecond),
    TxnId = <<"txn-4">>,
    
    DebitEntry = #ledger_entry{
        entry_id = <<"entry-debit-4">>,
        txn_id = TxnId,
        account_id = <<"account-1">>,
        entry_type = debit,
        amount = 0,  %% Zero amount!
        currency = 'USD',
        description = <<"Test debit">>,
        posted_at = Now
    },
    
    CreditEntry = #ledger_entry{
        entry_id = <<"entry-credit-4">>,
        txn_id = TxnId,
        account_id = <<"account-2">>,
        entry_type = credit,
        amount = 0,  %% Zero amount!
        currency = 'USD',
        description = <<"Test credit">>,
        posted_at = Now
    },
    
    F = fun() ->
        cb_ledger:post_entries(DebitEntry, CreditEntry)
    end,
    {atomic, {error, zero_amount}} = mnesia:transaction(F),
    ok.

%% Test: Get entries for transaction
get_entries_for_transaction_ok(_Config) ->
    Now = erlang:system_time(millisecond),
    TxnId = <<"txn-5">>,
    
    DebitEntry = #ledger_entry{
        entry_id = <<"entry-debit-5">>,
        txn_id = TxnId,
        account_id = <<"account-1">>,
        entry_type = debit,
        amount = 500,
        currency = 'USD',
        description = <<"Test debit">>,
        posted_at = Now
    },
    
    CreditEntry = #ledger_entry{
        entry_id = <<"entry-credit-5">>,
        txn_id = TxnId,
        account_id = <<"account-2">>,
        entry_type = credit,
        amount = 500,
        currency = 'USD',
        description = <<"Test credit">>,
        posted_at = Now
    },
    
    F = fun() ->
        cb_ledger:post_entries(DebitEntry, CreditEntry)
    end,
    {atomic, ok} = mnesia:transaction(F),
    
    {ok, Entries} = cb_ledger:get_entries_for_transaction(TxnId),
    ?assertEqual(2, length(Entries)),
    
    %% Verify one debit and one credit
    Debits = [E || E <- Entries, E#ledger_entry.entry_type =:= debit],
    Credits = [E || E <- Entries, E#ledger_entry.entry_type =:= credit],
    ?assertEqual(1, length(Debits)),
    ?assertEqual(1, length(Credits)),
    ok.

%% Test: Get entries for account
get_entries_for_account_ok(_Config) ->
    Now = erlang:system_time(millisecond),
    TxnId = <<"txn-6">>,
    AccountId = <<"account-3">>,

    Entry = #ledger_entry{
        entry_id = <<"entry-6">>,
        txn_id = TxnId,
        account_id = AccountId,
        entry_type = credit,
        amount = 750,
        currency = 'USD',
        description = <<"Test entry">>,
        posted_at = Now
    },

    F = fun() ->
        mnesia:write(Entry)
    end,
    {atomic, ok} = mnesia:transaction(F),

    {ok, Result} = cb_ledger:get_entries_for_account(AccountId, 1, 10),
    ?assertEqual(1, maps:get(total, Result)),
    ?assertEqual(1, length(maps:get(items, Result))),
    ok.

%% Test: Create chart account
create_chart_account_ok(_Config) ->
    {ok, Account} = cb_ledger:create_chart_account(<<"1000">>, <<"Cash">>, asset, undefined),
    ?assertEqual(<<"1000">>, Account#chart_account.code),
    ?assertEqual(asset, Account#chart_account.account_type),
    ok.

%% Test: Trial balance totals stay balanced
trial_balance_ok(_Config) ->
    Now = erlang:system_time(millisecond),
    TxnId = <<"txn-tb-1">>,

    DebitEntry = #ledger_entry{
        entry_id = <<"entry-tb-debit-1">>,
        txn_id = TxnId,
        account_id = <<"acc-tb-1">>,
        entry_type = debit,
        amount = 1250,
        currency = 'USD',
        description = <<"Trial balance debit">>,
        posted_at = Now
    },

    CreditEntry = #ledger_entry{
        entry_id = <<"entry-tb-credit-1">>,
        txn_id = TxnId,
        account_id = <<"acc-tb-2">>,
        entry_type = credit,
        amount = 1250,
        currency = 'USD',
        description = <<"Trial balance credit">>,
        posted_at = Now
    },

    {atomic, ok} = mnesia:transaction(fun() -> cb_ledger:post_entries(DebitEntry, CreditEntry) end),
    {ok, TB} = cb_ledger:get_trial_balance('USD'),

    ?assertEqual(1250, maps:get(total_debits, TB)),
    ?assertEqual(1250, maps:get(total_credits, TB)),
    ?assertEqual(true, maps:get(balanced, TB)),
    ok.

%% Test: Create and fetch balance snapshots
balance_snapshot_ok(_Config) ->
    {ok, Party} = cb_party:create_party(<<"Snapshot Party">>, <<"snapshot@example.com">>),
    {ok, Account} = cb_accounts:create_account(Party#party.party_id, <<"Snapshot Account">>, 'USD'),

    {ok, Snapshot} = cb_ledger:create_balance_snapshot(Account#account.account_id),
    ?assertEqual(Account#account.account_id, Snapshot#balance_snapshot.account_id),

    {ok, Result} = cb_ledger:get_balance_snapshots(Account#account.account_id, 1, 10),
    ?assertEqual(1, maps:get(total, Result)),
    ?assertEqual(1, length(maps:get(items, Result))),
    ok.
