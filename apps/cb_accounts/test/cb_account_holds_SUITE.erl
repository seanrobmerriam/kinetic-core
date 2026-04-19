-module(cb_account_holds_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    place_hold_ok/1,
    place_hold_account_not_found/1,
    place_hold_zero_amount/1,
    place_hold_closed_account/1,
    release_hold_ok/1,
    release_hold_not_found/1,
    release_hold_already_released/1,
    expire_holds_ok/1,
    expire_holds_no_expiry/1,
    list_holds_ok/1,
    list_holds_account_not_found/1,
    get_available_balance_no_holds/1,
    get_available_balance_with_holds/1,
    get_available_balance_released_hold_not_counted/1,
    payment_blocked_by_hold/1,
    payment_allowed_within_available_balance/1
]).

all() ->
    [
        place_hold_ok,
        place_hold_account_not_found,
        place_hold_zero_amount,
        place_hold_closed_account,
        release_hold_ok,
        release_hold_not_found,
        release_hold_already_released,
        expire_holds_ok,
        expire_holds_no_expiry,
        list_holds_ok,
        list_holds_account_not_found,
        get_available_balance_no_holds,
        get_available_balance_with_holds,
        get_available_balance_released_hold_not_counted,
        payment_blocked_by_hold,
        payment_allowed_within_available_balance
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
                  [party, account, account_hold, transaction, ledger_entry]),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

%% ─── Helpers ───────────────────────────────────────────────────────────────

setup_account() ->
    {ok, Party}   = cb_party:create_party(<<"Test Party">>, <<"holds@example.com">>),
    {ok, Account} = cb_accounts:create_account(Party#party.party_id, <<"Checking">>, 'USD'),
    Account.

%% ─── place_hold ─────────────────────────────────────────────────────────────

place_hold_ok(_Config) ->
    Account = setup_account(),
    {ok, Hold} = cb_account_holds:place_hold(Account#account.account_id, 500, <<"fraud investigation">>, undefined),
    ?assertEqual(Account#account.account_id, Hold#account_hold.account_id),
    ?assertEqual(500, Hold#account_hold.amount),
    ?assertEqual(active, Hold#account_hold.status),
    ?assertEqual(undefined, Hold#account_hold.expires_at),
    ok.

place_hold_account_not_found(_Config) ->
    FakeId = <<"00000000-0000-0000-0000-000000000000">>,
    {error, Reason} = cb_account_holds:place_hold(FakeId, 100, <<"test">>, undefined),
    ?assertEqual(account_not_found, Reason),
    ok.

place_hold_zero_amount(_Config) ->
    Account = setup_account(),
    {error, Reason} = cb_account_holds:place_hold(Account#account.account_id, 0, <<"test">>, undefined),
    ?assertEqual(zero_amount, Reason),
    ok.

place_hold_closed_account(_Config) ->
    Account = setup_account(),
    {ok, _} = cb_accounts:close_account(Account#account.account_id),
    {error, Reason} = cb_account_holds:place_hold(Account#account.account_id, 100, <<"test">>, undefined),
    ?assertEqual(account_closed, Reason),
    ok.

%% ─── release_hold ────────────────────────────────────────────────────────────

release_hold_ok(_Config) ->
    Account = setup_account(),
    {ok, Hold} = cb_account_holds:place_hold(Account#account.account_id, 300, <<"test">>, undefined),
    {ok, Released} = cb_account_holds:release_hold(Hold#account_hold.hold_id),
    ?assertEqual(released, Released#account_hold.status),
    ?assertNotEqual(undefined, Released#account_hold.released_at),
    ok.

release_hold_not_found(_Config) ->
    FakeId = <<"00000000-0000-0000-0000-000000000000">>,
    {error, Reason} = cb_account_holds:release_hold(FakeId),
    ?assertEqual(hold_not_found, Reason),
    ok.

release_hold_already_released(_Config) ->
    Account = setup_account(),
    {ok, Hold} = cb_account_holds:place_hold(Account#account.account_id, 200, <<"test">>, undefined),
    {ok, _} = cb_account_holds:release_hold(Hold#account_hold.hold_id),
    {error, Reason} = cb_account_holds:release_hold(Hold#account_hold.hold_id),
    ?assertEqual(hold_already_released, Reason),
    ok.

%% ─── expire_holds ────────────────────────────────────────────────────────────

expire_holds_ok(_Config) ->
    Account = setup_account(),
    PastTs = erlang:system_time(millisecond) - 10000,
    {ok, Hold} = cb_account_holds:place_hold(Account#account.account_id, 100, <<"expiring">>, PastTs),
    {ok, Count} = cb_account_holds:expire_holds(Account#account.account_id),
    ?assert(Count >= 1),
    %% The hold should now be expired
    {ok, Holds} = cb_account_holds:list_holds(Account#account.account_id),
    [H] = Holds,
    ?assertEqual(expired, H#account_hold.status),
    _ = Hold,
    ok.

expire_holds_no_expiry(_Config) ->
    Account = setup_account(),
    {ok, _Hold} = cb_account_holds:place_hold(Account#account.account_id, 100, <<"no expiry">>, undefined),
    {ok, Count} = cb_account_holds:expire_holds(Account#account.account_id),
    ?assertEqual(0, Count),
    ok.

%% ─── list_holds ──────────────────────────────────────────────────────────────

list_holds_ok(_Config) ->
    Account = setup_account(),
    {ok, _H1} = cb_account_holds:place_hold(Account#account.account_id, 100, <<"hold 1">>, undefined),
    {ok, _H2} = cb_account_holds:place_hold(Account#account.account_id, 200, <<"hold 2">>, undefined),
    {ok, Holds} = cb_account_holds:list_holds(Account#account.account_id),
    ?assertEqual(2, length(Holds)),
    ok.

list_holds_account_not_found(_Config) ->
    FakeId = <<"00000000-0000-0000-0000-000000000000">>,
    {error, Reason} = cb_account_holds:list_holds(FakeId),
    ?assertEqual(account_not_found, Reason),
    ok.

%% ─── get_available_balance ───────────────────────────────────────────────────

get_available_balance_no_holds(_Config) ->
    Account = setup_account(),
    {ok, _} = cb_payments:deposit(<<"dep-holds-1">>, Account#account.account_id, 1000, 'USD', <<"Seed">>),
    {ok, Avail} = cb_account_holds:get_available_balance(Account#account.account_id),
    ?assertEqual(1000, Avail),
    ok.

get_available_balance_with_holds(_Config) ->
    Account = setup_account(),
    {ok, _} = cb_payments:deposit(<<"dep-holds-2">>, Account#account.account_id, 1000, 'USD', <<"Seed">>),
    {ok, _Hold} = cb_account_holds:place_hold(Account#account.account_id, 300, <<"compliance">>, undefined),
    {ok, Avail} = cb_account_holds:get_available_balance(Account#account.account_id),
    ?assertEqual(700, Avail),
    ok.

get_available_balance_released_hold_not_counted(_Config) ->
    Account = setup_account(),
    {ok, _} = cb_payments:deposit(<<"dep-holds-3">>, Account#account.account_id, 1000, 'USD', <<"Seed">>),
    {ok, Hold} = cb_account_holds:place_hold(Account#account.account_id, 400, <<"pending auth">>, undefined),
    {ok, _} = cb_account_holds:release_hold(Hold#account_hold.hold_id),
    {ok, Avail} = cb_account_holds:get_available_balance(Account#account.account_id),
    ?assertEqual(1000, Avail),
    ok.

%% ─── payment integration ─────────────────────────────────────────────────────

payment_blocked_by_hold(_Config) ->
    Account = setup_account(),
    {ok, _} = cb_payments:deposit(<<"dep-holds-4">>, Account#account.account_id, 1000, 'USD', <<"Seed">>),
    %% Hold 800, leaving only 200 available
    {ok, _Hold} = cb_account_holds:place_hold(Account#account.account_id, 800, <<"large hold">>, undefined),
    %% Attempt to withdraw 500 (more than the 200 available)
    {error, Reason} = cb_payments:withdraw(<<"wd-blocked-1">>, Account#account.account_id, 500, 'USD', <<"blocked withdrawal">>),
    ?assertEqual(insufficient_funds, Reason),
    ok.

payment_allowed_within_available_balance(_Config) ->
    Account = setup_account(),
    {ok, _} = cb_payments:deposit(<<"dep-holds-5">>, Account#account.account_id, 1000, 'USD', <<"Seed">>),
    %% Hold 400, leaving 600 available
    {ok, _Hold} = cb_account_holds:place_hold(Account#account.account_id, 400, <<"partial hold">>, undefined),
    %% Withdraw only 500 — less than the 600 available
    {ok, Txn} = cb_payments:withdraw(<<"wd-allowed-1">>, Account#account.account_id, 500, 'USD', <<"allowed withdrawal">>),
    ?assertEqual(posted, Txn#transaction.status),
    ok.
