-module(cb_stp_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    stp_straight_through/1,
    stp_exceeds_threshold/1,
    stp_kyc_not_approved/1,
    stp_account_not_active/1,
    exception_enqueue_ok/1,
    exception_list_pending/1,
    exception_resolve_approved/1,
    exception_resolve_rejected/1,
    exception_already_resolved/1
]).

all() ->
    [
        stp_straight_through,
        stp_exceeds_threshold,
        stp_kyc_not_approved,
        stp_account_not_active,
        exception_enqueue_ok,
        exception_list_pending,
        exception_resolve_approved,
        exception_resolve_rejected,
        exception_already_resolved
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

make_order(PartyId, SrcId, Amount) ->
    #payment_order{
        payment_id        = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
        idempotency_key   = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
        party_id          = PartyId,
        source_account_id = SrcId,
        dest_account_id   = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
        amount            = Amount,
        currency          = 'USD',
        description       = <<"Test">>,
        status            = initiated,
        stp_decision      = undefined,
        failure_reason    = undefined,
        retry_count       = 0,
        created_at        = erlang:system_time(millisecond),
        updated_at        = erlang:system_time(millisecond)
    }.

setup_approved_party_with_account() ->
    {ok, Party} = cb_party:create_party(<<"STP Test">>, <<"stp@example.com">>),
    {ok, P2} = cb_party:update_kyc_status(Party#party.party_id, approved, <<"Verified">>),
    {ok, Acc} = cb_accounts:create_account(P2#party.party_id, <<"STP Acc">>, 'USD'),
    {P2, Acc}.

stp_straight_through(_Config) ->
    {Party, Acc} = setup_approved_party_with_account(),
    Order = make_order(Party#party.party_id, Acc#account.account_id, 50_000),
    ?assertEqual(straight_through, cb_stp:evaluate(Order)),
    ok.

stp_exceeds_threshold(_Config) ->
    {Party, Acc} = setup_approved_party_with_account(),
    Order = make_order(Party#party.party_id, Acc#account.account_id, 200_000),
    {exception, _Reason} = cb_stp:evaluate(Order),
    ok.

stp_kyc_not_approved(_Config) ->
    {ok, Party} = cb_party:create_party(<<"STP KYC">>, <<"stp_kyc@example.com">>),
    {ok, Acc} = cb_accounts:create_account(Party#party.party_id, <<"STP KYC Acc">>, 'USD'),
    Order = make_order(Party#party.party_id, Acc#account.account_id, 1000),
    {exception, _Reason} = cb_stp:evaluate(Order),
    ok.

stp_account_not_active(_Config) ->
    {Party, Acc} = setup_approved_party_with_account(),
    {ok, _} = cb_accounts:freeze_account(Acc#account.account_id),
    Order = make_order(Party#party.party_id, Acc#account.account_id, 1000),
    {exception, _Reason} = cb_stp:evaluate(Order),
    ok.

exception_enqueue_ok(_Config) ->
    PaymentId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
    {ok, Item} = cb_exception_queue:enqueue(PaymentId, <<"High amount">>),
    ?assertEqual(pending, Item#exception_item.status),
    ?assertEqual(PaymentId, Item#exception_item.payment_id),
    ok.

exception_list_pending(_Config) ->
    {ok, _} = cb_exception_queue:enqueue(<<"p1">>, <<"Reason 1">>),
    {ok, _} = cb_exception_queue:enqueue(<<"p2">>, <<"Reason 2">>),
    Pending = cb_exception_queue:list_pending(),
    ?assertEqual(2, length(Pending)),
    ok.

exception_resolve_approved(_Config) ->
    {Party, Src} = setup_approved_party_with_account(),
    {ok, Dst} = cb_accounts:create_account(Party#party.party_id, <<"Dst">>, 'USD'),
    {ok, _} = cb_payments:deposit(<<"seed-stp-1">>, Src#account.account_id, 100_000, 'USD', <<"Seed">>),
    {ok, Order} = cb_payment_orders:initiate(
        <<"stp-po-1">>, Party#party.party_id,
        Src#account.account_id, Dst#account.account_id, 200_000
    ),
    ?assertEqual(validating, Order#payment_order.status),
    [Item] = cb_exception_queue:list_pending(),
    {ok, Resolved} = cb_exception_queue:resolve(Item#exception_item.item_id, approved, <<"Manually approved">>),
    ?assertEqual(resolved, Resolved#exception_item.status),
    ?assertEqual(approved, Resolved#exception_item.resolution),
    ok.

exception_resolve_rejected(_Config) ->
    {ok, Item} = cb_exception_queue:enqueue(<<"pay-rej">>, <<"Suspicious">>),
    {ok, Resolved} = cb_exception_queue:resolve(Item#exception_item.item_id, rejected, <<"Fraud suspected">>),
    ?assertEqual(resolved, Resolved#exception_item.status),
    ?assertEqual(rejected, Resolved#exception_item.resolution),
    ok.

exception_already_resolved(_Config) ->
    {ok, Item} = cb_exception_queue:enqueue(<<"pay-dup">>, <<"Test">>),
    {ok, _} = cb_exception_queue:resolve(Item#exception_item.item_id, rejected, <<"First">>),
    {error, already_resolved} = cb_exception_queue:resolve(Item#exception_item.item_id, approved, <<"Second">>),
    ok.
