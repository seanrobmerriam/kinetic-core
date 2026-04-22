-module(cb_payment_orders_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    initiate_straight_through/1,
    initiate_idempotent/1,
    initiate_invalid_amount/1,
    get_payment_ok/1,
    get_payment_not_found/1,
    cancel_initiated/1,
    cancel_completed/1,
    retry_failed/1,
    retry_completed/1,
    list_payments_for_party/1
]).

all() ->
    [
        initiate_straight_through,
        initiate_idempotent,
        initiate_invalid_amount,
        get_payment_ok,
        get_payment_not_found,
        cancel_initiated,
        cancel_completed,
        retry_failed,
        retry_completed,
        list_payments_for_party
    ].

init_per_suite(Config) ->
    mnesia:start(),
    cb_schema:create_tables(),
    cb_currency:seed_defaults(),
    Config.

end_per_suite(_Config) ->
    mnesia:stop(),
    mnesia:delete_schema([node()]),
    ok.

init_per_testcase(_TestCase, Config) ->
    lists:foreach(fun(T) -> mnesia:clear_table(T) end,
                  [party, party_audit, account, transaction, ledger_entry,
                   payment_order, exception_item]),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

setup_party_with_accounts() ->
    {ok, Party} = cb_party:create_party(<<"Test Party">>, <<"test_po@example.com">>),
    {ok, _} = cb_party:update_kyc_status(Party#party.party_id, approved, <<"Verified">>),
    {ok, Src} = cb_accounts:create_account(Party#party.party_id, <<"Source">>, 'USD'),
    {ok, Dst} = cb_accounts:create_account(Party#party.party_id, <<"Dest">>, 'USD'),
    {ok, _} = cb_payments:deposit(<<"seed-po-1">>, Src#account.account_id, 100_000, 'USD', <<"Seed">>),
    {Party, Src, Dst}.

initiate_straight_through(_Config) ->
    {Party, Src, Dst} = setup_party_with_accounts(),
    {ok, Order} = cb_payment_orders:initiate(
        <<"po-1">>, Party#party.party_id,
        Src#account.account_id, Dst#account.account_id, 50_000
    ),
    ?assertEqual(completed, Order#payment_order.status),
    ?assertEqual(straight_through, Order#payment_order.stp_decision),
    ok.

initiate_idempotent(_Config) ->
    {Party, Src, Dst} = setup_party_with_accounts(),
    {ok, Order1} = cb_payment_orders:initiate(
        <<"po-idem">>, Party#party.party_id,
        Src#account.account_id, Dst#account.account_id, 1000
    ),
    {ok, Order2} = cb_payment_orders:initiate(
        <<"po-idem">>, Party#party.party_id,
        Src#account.account_id, Dst#account.account_id, 1000
    ),
    ?assertEqual(Order1#payment_order.payment_id, Order2#payment_order.payment_id),
    ok.

initiate_invalid_amount(_Config) ->
    {Party, Src, Dst} = setup_party_with_accounts(),
    {error, invalid_amount} = cb_payment_orders:initiate(
        <<"po-bad">>, Party#party.party_id,
        Src#account.account_id, Dst#account.account_id, 0
    ),
    ok.

get_payment_ok(_Config) ->
    {Party, Src, Dst} = setup_party_with_accounts(),
    {ok, Order} = cb_payment_orders:initiate(
        <<"po-get-1">>, Party#party.party_id,
        Src#account.account_id, Dst#account.account_id, 500
    ),
    {ok, Got} = cb_payment_orders:get_payment(Order#payment_order.payment_id),
    ?assertEqual(Order#payment_order.payment_id, Got#payment_order.payment_id),
    ok.

get_payment_not_found(_Config) ->
    {error, not_found} = cb_payment_orders:get_payment(<<"nonexistent">>),
    ok.

cancel_initiated(_Config) ->
    {Party, Src, Dst} = setup_party_with_accounts(),
    {ok, Order} = cb_payment_orders:initiate(
        <<"po-cancel-1">>, Party#party.party_id,
        Src#account.account_id, Dst#account.account_id, 100_001
    ),
    ?assertEqual(validating, Order#payment_order.status),
    {ok, Cancelled} = cb_payment_orders:cancel_payment(Order#payment_order.payment_id),
    ?assertEqual(cancelled, Cancelled#payment_order.status),
    ok.

cancel_completed(_Config) ->
    {Party, Src, Dst} = setup_party_with_accounts(),
    {ok, Order} = cb_payment_orders:initiate(
        <<"po-cancel-2">>, Party#party.party_id,
        Src#account.account_id, Dst#account.account_id, 500
    ),
    ?assertEqual(completed, Order#payment_order.status),
    {error, cannot_cancel} = cb_payment_orders:cancel_payment(Order#payment_order.payment_id),
    ok.

retry_failed(_Config) ->
    {Party, Src, Dst} = setup_party_with_accounts(),
    {ok, Order} = cb_payment_orders:initiate(
        <<"po-retry-1">>, Party#party.party_id,
        Src#account.account_id, Dst#account.account_id, 1000
    ),
    Now = erlang:system_time(millisecond),
    Failed = Order#payment_order{
        status         = failed,
        failure_reason = <<"test failure">>,
        updated_at     = Now
    },
    {atomic, ok} = mnesia:transaction(fun() ->
        mnesia:write(payment_order, Failed, write)
    end),
    {ok, Retried} = cb_payment_orders:retry_payment(Order#payment_order.payment_id),
    ?assert(Retried#payment_order.retry_count > 0),
    ok.

retry_completed(_Config) ->
    {Party, Src, Dst} = setup_party_with_accounts(),
    {ok, Order} = cb_payment_orders:initiate(
        <<"po-retry-2">>, Party#party.party_id,
        Src#account.account_id, Dst#account.account_id, 500
    ),
    ?assertEqual(completed, Order#payment_order.status),
    {error, cannot_retry} = cb_payment_orders:retry_payment(Order#payment_order.payment_id),
    ok.

list_payments_for_party(_Config) ->
    {Party, Src, Dst} = setup_party_with_accounts(),
    {ok, _} = cb_payment_orders:initiate(
        <<"po-list-1">>, Party#party.party_id,
        Src#account.account_id, Dst#account.account_id, 100
    ),
    {ok, _} = cb_payment_orders:initiate(
        <<"po-list-2">>, Party#party.party_id,
        Src#account.account_id, Dst#account.account_id, 200
    ),
    Orders = cb_payment_orders:list_payments_for_party(Party#party.party_id),
    ?assertEqual(2, length(Orders)),
    ok.
