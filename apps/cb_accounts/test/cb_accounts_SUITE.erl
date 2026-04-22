-module(cb_accounts_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    create_account_ok/1,
    create_account_party_not_found/1,
    create_account_unsupported_currency/1,
    get_account_ok/1,
    get_account_not_found/1,
    list_accounts_for_party_ok/1,
    freeze_account_ok/1,
    freeze_account_already_frozen/1,
    unfreeze_account_ok/1,
    unfreeze_account_not_frozen/1,
    close_account_zero_balance/1,
    close_account_nonzero_balance/1,
    get_balance_ok/1
]).

all() ->
    [
        create_account_ok,
        create_account_party_not_found,
        create_account_unsupported_currency,
        get_account_ok,
        get_account_not_found,
        list_accounts_for_party_ok,
        freeze_account_ok,
        freeze_account_already_frozen,
        unfreeze_account_ok,
        unfreeze_account_not_frozen,
        close_account_zero_balance,
        close_account_nonzero_balance,
        get_balance_ok
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
                  [party, party_audit, account, transaction, ledger_entry]),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

%% Test: Create account with valid data
create_account_ok(_Config) ->
    {ok, Party} = cb_party:create_party(<<"Test Party">>, <<"test@example.com">>),
    {ok, Account} = cb_accounts:create_account(Party#party.party_id, <<"Main Checking">>, 'USD'),
    ?assertEqual(<<"Main Checking">>, Account#account.name),
    ?assertEqual('USD', Account#account.currency),
    ?assertEqual(0, Account#account.balance),
    ?assertEqual(active, Account#account.status),
    ?assertEqual(Party#party.party_id, Account#account.party_id),
    ok.

%% Test: Create account for non-existent party
create_account_party_not_found(_Config) ->
    FakeId = <<"00000000-0000-0000-0000-000000000000">>,
    {error, Reason} = cb_accounts:create_account(FakeId, <<"Test">>, 'USD'),
    ?assertEqual(party_not_found, Reason),
    ok.

%% Test: Create account with unsupported currency
create_account_unsupported_currency(_Config) ->
    {ok, Party} = cb_party:create_party(<<"Test Party">>, <<"test@example.com">>),
    {error, Reason} = cb_accounts:create_account(Party#party.party_id, <<"Test">>, 'XYZ'),
    ?assertEqual(unsupported_currency, Reason),
    ok.

%% Test: Get existing account
get_account_ok(_Config) ->
    {ok, Party} = cb_party:create_party(<<"Test Party">>, <<"test@example.com">>),
    {ok, Account} = cb_accounts:create_account(Party#party.party_id, <<"Main">>, 'USD'),
    {ok, Retrieved} = cb_accounts:get_account(Account#account.account_id),
    ?assertEqual(Account#account.account_id, Retrieved#account.account_id),
    ?assertEqual(<<"Main">>, Retrieved#account.name),
    ok.

%% Test: Get non-existent account
get_account_not_found(_Config) ->
    FakeId = <<"00000000-0000-0000-0000-000000000000">>,
    {error, Reason} = cb_accounts:get_account(FakeId),
    ?assertEqual(account_not_found, Reason),
    ok.

%% Test: List accounts for party
list_accounts_for_party_ok(_Config) ->
    {ok, Party} = cb_party:create_party(<<"Test Party">>, <<"test@example.com">>),
    {ok, _A1} = cb_accounts:create_account(Party#party.party_id, <<"Account 1">>, 'USD'),
    {ok, _A2} = cb_accounts:create_account(Party#party.party_id, <<"Account 2">>, 'EUR'),
    
    {ok, Result} = cb_accounts:list_accounts_for_party(Party#party.party_id, 1, 10),
    ?assertEqual(2, maps:get(total, Result)),
    ?assertEqual(2, length(maps:get(items, Result))),
    ok.

%% Test: Freeze an active account
freeze_account_ok(_Config) ->
    {ok, Party} = cb_party:create_party(<<"Test Party">>, <<"test@example.com">>),
    {ok, Account} = cb_accounts:create_account(Party#party.party_id, <<"Main">>, 'USD'),
    ?assertEqual(active, Account#account.status),
    
    {ok, Frozen} = cb_accounts:freeze_account(Account#account.account_id),
    ?assertEqual(frozen, Frozen#account.status),
    ok.

%% Test: Freeze already frozen account
freeze_account_already_frozen(_Config) ->
    {ok, Party} = cb_party:create_party(<<"Test Party">>, <<"test@example.com">>),
    {ok, Account} = cb_accounts:create_account(Party#party.party_id, <<"Main">>, 'USD'),
    {ok, _Frozen} = cb_accounts:freeze_account(Account#account.account_id),
    
    {error, Reason} = cb_accounts:freeze_account(Account#account.account_id),
    ?assertEqual(account_already_frozen, Reason),
    ok.

%% Test: Unfreeze a frozen account
unfreeze_account_ok(_Config) ->
    {ok, Party} = cb_party:create_party(<<"Test Party">>, <<"test@example.com">>),
    {ok, Account} = cb_accounts:create_account(Party#party.party_id, <<"Main">>, 'USD'),
    {ok, Frozen} = cb_accounts:freeze_account(Account#account.account_id),
    ?assertEqual(frozen, Frozen#account.status),
    
    {ok, Unfrozen} = cb_accounts:unfreeze_account(Account#account.account_id),
    ?assertEqual(active, Unfrozen#account.status),
    ok.

%% Test: Unfreeze account that is not frozen
unfreeze_account_not_frozen(_Config) ->
    {ok, Party} = cb_party:create_party(<<"Test Party">>, <<"test@example.com">>),
    {ok, Account} = cb_accounts:create_account(Party#party.party_id, <<"Main">>, 'USD'),
    
    {error, Reason} = cb_accounts:unfreeze_account(Account#account.account_id),
    ?assertEqual(account_not_frozen, Reason),
    ok.

%% Test: Close account with zero balance
close_account_zero_balance(_Config) ->
    {ok, Party} = cb_party:create_party(<<"Test Party">>, <<"test@example.com">>),
    {ok, Account} = cb_accounts:create_account(Party#party.party_id, <<"Main">>, 'USD'),
    ?assertEqual(0, Account#account.balance),
    
    {ok, Closed} = cb_accounts:close_account(Account#account.account_id),
    ?assertEqual(closed, Closed#account.status),
    ok.

%% Test: Close account with non-zero balance
close_account_nonzero_balance(_Config) ->
    {ok, Party} = cb_party:create_party(<<"Test Party">>, <<"test@example.com">>),
    {ok, Account} = cb_accounts:create_account(Party#party.party_id, <<"Main">>, 'USD'),
    
    %% Deposit some funds
    {ok, _Txn} = cb_payments:deposit(<<"dep-1">>, Account#account.account_id, 1000, 'USD', <<"Initial deposit">>),
    
    {error, Reason} = cb_accounts:close_account(Account#account.account_id),
    ?assertEqual(account_has_balance, Reason),
    ok.

%% Test: Get balance
get_balance_ok(_Config) ->
    {ok, Party} = cb_party:create_party(<<"Test Party">>, <<"test@example.com">>),
    {ok, Account} = cb_accounts:create_account(Party#party.party_id, <<"Main">>, 'USD'),
    {ok, _Txn} = cb_payments:deposit(<<"dep-1">>, Account#account.account_id, 1000, 'USD', <<"Initial deposit">>),
    
    {ok, Result} = cb_accounts:get_balance(Account#account.account_id),
    ?assertEqual(1000, maps:get(balance, Result)),
    ?assertEqual('USD', maps:get(currency, Result)),
    ?assertEqual(<<"$10.00">>, maps:get(balance_formatted, Result)),
    ok.
