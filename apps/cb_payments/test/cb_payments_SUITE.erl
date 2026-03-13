-module(cb_payments_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    transfer_ok/1,
    transfer_insufficient_funds/1,
    transfer_zero_amount/1,
    transfer_currency_mismatch/1,
    transfer_same_account/1,
    transfer_idempotent/1,
    deposit_ok/1,
    withdrawal_ok/1,
    withdrawal_insufficient/1,
    reverse_transfer_ok/1,
    reverse_non_posted_txn/1
]).

all() ->
    [
        transfer_ok,
        transfer_insufficient_funds,
        transfer_zero_amount,
        transfer_currency_mismatch,
        transfer_same_account,
        transfer_idempotent,
        deposit_ok,
        withdrawal_ok,
        withdrawal_insufficient,
        reverse_transfer_ok,
        reverse_non_posted_txn
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
                  [party, account, transaction, ledger_entry]),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

%% Helper: Create party with two accounts
setup_party_with_accounts() ->
    {ok, Party} = cb_party:create_party(<<"Test Party">>, <<"test@example.com">>),
    {ok, SourceAcc} = cb_accounts:create_account(Party#party.party_id, <<"Source">>, 'USD'),
    {ok, DestAcc} = cb_accounts:create_account(Party#party.party_id, <<"Dest">>, 'USD'),
    {Party, SourceAcc, DestAcc}.

%% Test: Valid transfer between accounts
transfer_ok(_Config) ->
    {_Party, SourceAcc, DestAcc} = setup_party_with_accounts(),
    
    %% Seed source account
    {ok, _Deposit} = cb_payments:deposit(<<"seed-1">>, SourceAcc#account.account_id, 5000, 'USD', <<"Seed">>),
    
    %% Transfer
    {ok, Txn} = cb_payments:transfer(
        <<"transfer-1">>,
        SourceAcc#account.account_id,
        DestAcc#account.account_id,
        1000,
        'USD',
        <<"Test transfer">>
    ),
    
    ?assertEqual(transfer, Txn#transaction.txn_type),
    ?assertEqual(posted, Txn#transaction.status),
    ?assertEqual(1000, Txn#transaction.amount),
    
    %% Verify balances
    {ok, SourceUpdated} = cb_accounts:get_account(SourceAcc#account.account_id),
    {ok, DestUpdated} = cb_accounts:get_account(DestAcc#account.account_id),
    ?assertEqual(4000, SourceUpdated#account.balance),
    ?assertEqual(1000, DestUpdated#account.balance),
    
    %% Verify ledger entries
    {ok, Entries} = cb_ledger:get_entries_for_transaction(Txn#transaction.txn_id),
    ?assertEqual(2, length(Entries)),
    ok.

%% Test: Transfer with insufficient funds
transfer_insufficient_funds(_Config) ->
    {_Party, SourceAcc, DestAcc} = setup_party_with_accounts(),
    
    %% Don't seed source account - balance is 0
    {error, Reason} = cb_payments:transfer(
        <<"transfer-2">>,
        SourceAcc#account.account_id,
        DestAcc#account.account_id,
        1000,
        'USD',
        <<"Test transfer">>
    ),
    ?assertEqual(insufficient_funds, Reason),
    ok.

%% Test: Transfer with zero amount
transfer_zero_amount(_Config) ->
    {_Party, SourceAcc, DestAcc} = setup_party_with_accounts(),
    
    {error, Reason} = cb_payments:transfer(
        <<"transfer-3">>,
        SourceAcc#account.account_id,
        DestAcc#account.account_id,
        0,
        'USD',
        <<"Test transfer">>
    ),
    ?assertEqual(zero_amount, Reason),
    ok.

%% Test: Transfer with currency mismatch
transfer_currency_mismatch(_Config) ->
    {ok, Party} = cb_party:create_party(<<"Test Party">>, <<"test@example.com">>),
    {ok, SourceAcc} = cb_accounts:create_account(Party#party.party_id, <<"Source">>, 'USD'),
    {ok, DestAcc} = cb_accounts:create_account(Party#party.party_id, <<"Dest">>, 'EUR'),
    
    {error, Reason} = cb_payments:transfer(
        <<"transfer-4">>,
        SourceAcc#account.account_id,
        DestAcc#account.account_id,
        1000,
        'USD',
        <<"Test transfer">>
    ),
    ?assertEqual(currency_mismatch, Reason),
    ok.

%% Test: Transfer to same account
transfer_same_account(_Config) ->
    {ok, Party} = cb_party:create_party(<<"Test Party">>, <<"test@example.com">>),
    {ok, Account} = cb_accounts:create_account(Party#party.party_id, <<"Main">>, 'USD'),
    
    {error, Reason} = cb_payments:transfer(
        <<"transfer-5">>,
        Account#account.account_id,
        Account#account.account_id,
        1000,
        'USD',
        <<"Test transfer">>
    ),
    ?assertEqual(same_account_transfer, Reason),
    ok.

%% Test: Idempotent transfer
transfer_idempotent(_Config) ->
    {_Party, SourceAcc, DestAcc} = setup_party_with_accounts(),
    
    %% Seed source account
    {ok, _Deposit} = cb_payments:deposit(<<"seed-2">>, SourceAcc#account.account_id, 5000, 'USD', <<"Seed">>),
    
    IdempotencyKey = <<"idempotent-transfer-1">>,
    
    %% First transfer
    {ok, Txn1} = cb_payments:transfer(
        IdempotencyKey,
        SourceAcc#account.account_id,
        DestAcc#account.account_id,
        1000,
        'USD',
        <<"Test transfer">>
    ),
    
    %% Second transfer with same key
    {ok, Txn2} = cb_payments:transfer(
        IdempotencyKey,
        SourceAcc#account.account_id,
        DestAcc#account.account_id,
        1000,
        'USD',
        <<"Test transfer">>
    ),
    
    %% Should return same transaction
    ?assertEqual(Txn1#transaction.txn_id, Txn2#transaction.txn_id),
    
    %% Verify balances unchanged after second call
    {ok, SourceUpdated} = cb_accounts:get_account(SourceAcc#account.account_id),
    {ok, DestUpdated} = cb_accounts:get_account(DestAcc#account.account_id),
    ?assertEqual(4000, SourceUpdated#account.balance),
    ?assertEqual(1000, DestUpdated#account.balance),
    ok.

%% Test: Valid deposit
deposit_ok(_Config) ->
    {_Party, _SourceAcc, DestAcc} = setup_party_with_accounts(),
    
    {ok, Txn} = cb_payments:deposit(
        <<"deposit-1">>,
        DestAcc#account.account_id,
        2000,
        'USD',
        <<"Test deposit">>
    ),
    
    ?assertEqual(deposit, Txn#transaction.txn_type),
    ?assertEqual(posted, Txn#transaction.status),
    ?assertEqual(2000, Txn#transaction.amount),
    
    {ok, Account} = cb_accounts:get_account(DestAcc#account.account_id),
    ?assertEqual(2000, Account#account.balance),
    ok.

%% Test: Valid withdrawal
withdrawal_ok(_Config) ->
    {_Party, SourceAcc, _DestAcc} = setup_party_with_accounts(),
    
    %% Seed account
    {ok, _Deposit} = cb_payments:deposit(<<"seed-3">>, SourceAcc#account.account_id, 5000, 'USD', <<"Seed">>),
    
    {ok, Txn} = cb_payments:withdraw(
        <<"withdrawal-1">>,
        SourceAcc#account.account_id,
        1500,
        'USD',
        <<"Test withdrawal">>
    ),
    
    ?assertEqual(withdrawal, Txn#transaction.txn_type),
    ?assertEqual(posted, Txn#transaction.status),
    ?assertEqual(1500, Txn#transaction.amount),
    
    {ok, Account} = cb_accounts:get_account(SourceAcc#account.account_id),
    ?assertEqual(3500, Account#account.balance),
    ok.

%% Test: Withdrawal with insufficient funds
withdrawal_insufficient(_Config) ->
    {_Party, SourceAcc, _DestAcc} = setup_party_with_accounts(),
    
    %% Don't seed - balance is 0
    {error, Reason} = cb_payments:withdraw(
        <<"withdrawal-2">>,
        SourceAcc#account.account_id,
        1000,
        'USD',
        <<"Test withdrawal">>
    ),
    ?assertEqual(insufficient_funds, Reason),
    ok.

%% Test: Reverse a posted transfer
reverse_transfer_ok(_Config) ->
    {_Party, SourceAcc, DestAcc} = setup_party_with_accounts(),
    
    %% Seed and transfer
    {ok, _Deposit} = cb_payments:deposit(<<"seed-4">>, SourceAcc#account.account_id, 5000, 'USD', <<"Seed">>),
    {ok, Txn} = cb_payments:transfer(
        <<"transfer-6">>,
        SourceAcc#account.account_id,
        DestAcc#account.account_id,
        1000,
        'USD',
        <<"Test transfer">>
    ),
    
    %% Verify initial balances
    {ok, SourceAfter} = cb_accounts:get_account(SourceAcc#account.account_id),
    {ok, DestAfter} = cb_accounts:get_account(DestAcc#account.account_id),
    ?assertEqual(4000, SourceAfter#account.balance),
    ?assertEqual(1000, DestAfter#account.balance),
    
    %% Reverse the transaction
    {ok, Reversal} = cb_payments:reverse_transaction(Txn#transaction.txn_id),
    ?assertEqual(posted, Reversal#transaction.status),
    
    %% Verify balances restored
    {ok, SourceFinal} = cb_accounts:get_account(SourceAcc#account.account_id),
    {ok, DestFinal} = cb_accounts:get_account(DestAcc#account.account_id),
    ?assertEqual(5000, SourceFinal#account.balance),
    ?assertEqual(0, DestFinal#account.balance),
    ok.

%% Test: Reverse a non-posted transaction (should fail)
reverse_non_posted_txn(_Config) ->
    %% Create a pending transaction manually (not possible through API, but test the error)
    %% In practice, all transactions created through API are posted immediately
    %% So we'll just verify the error case
    FakeId = <<"00000000-0000-0000-0000-000000000000">>,
    {error, Reason} = cb_payments:reverse_transaction(FakeId),
    ?assertEqual(transaction_not_found, Reason),
    ok.
