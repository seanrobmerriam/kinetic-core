%% @doc CT tests for cb_stp_metrics (TASK-053 — STP reporting).
-module(cb_stp_metrics_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    stp_rate_empty_tables/1,
    stp_rate_with_exceptions/1,
    exception_reasons_empty/1,
    exception_reasons_tally/1,
    sla_compliance_no_resolved/1,
    sla_compliance_all_within/1,
    sla_compliance_mixed/1,
    recent_activity_returns_n_most_recent/1
]).

all() ->
    [
        stp_rate_empty_tables,
        stp_rate_with_exceptions,
        exception_reasons_empty,
        exception_reasons_tally,
        sla_compliance_no_resolved,
        sla_compliance_all_within,
        sla_compliance_mixed,
        recent_activity_returns_n_most_recent
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
                  [party, party_audit, account, transaction, payment_order, exception_item]),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

make_order() ->
    Now = erlang:system_time(millisecond),
    PId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
    #payment_order{
        payment_id        = PId,
        idempotency_key   = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
        party_id          = <<"metrics-party">>,
        source_account_id = <<"acc-src">>,
        dest_account_id   = <<"acc-dst">>,
        amount            = 10_000,
        currency          = 'USD',
        description       = <<"Metrics test">>,
        status            = initiated,
        stp_decision      = undefined,
        failure_reason    = undefined,
        retry_count       = 0,
        created_at        = Now,
        updated_at        = Now
    }.

write_order(Order) ->
    {atomic, ok} = mnesia:transaction(fun() ->
        mnesia:write(payment_order, Order, write)
    end),
    Order.

%%% ---------------------------------------------------------------- TESTS ---

stp_rate_empty_tables(_Config) ->
    Rate = cb_stp_metrics:stp_rate(),
    ?assertEqual(0, maps:get(total, Rate)),
    ?assertEqual(0, maps:get(straight_through, Rate)),
    ?assertEqual(0, maps:get(exception, Rate)),
    ?assertEqual(0, maps:get(rate_bps, Rate)).

stp_rate_with_exceptions(_Config) ->
    O1 = write_order(make_order()),
    O2 = write_order(make_order()),
    {ok, _} = cb_exception_queue:enqueue(O1#payment_order.payment_id, <<"Reason A">>),
    Rate = cb_stp_metrics:stp_rate(),
    ?assertEqual(2, maps:get(total, Rate)),
    ?assertEqual(1, maps:get(exception, Rate)),
    ?assertEqual(1, maps:get(straight_through, Rate)),
    ?assertEqual(5_000, maps:get(rate_bps, Rate)),
    %% Satisfy compiler — O2 used
    _ = O2.

exception_reasons_empty(_Config) ->
    ?assertEqual([], cb_stp_metrics:exception_reasons()).

exception_reasons_tally(_Config) ->
    O1 = write_order(make_order()),
    O2 = write_order(make_order()),
    O3 = write_order(make_order()),
    {ok, _} = cb_exception_queue:enqueue(O1#payment_order.payment_id, <<"Amount">>),
    {ok, _} = cb_exception_queue:enqueue(O2#payment_order.payment_id, <<"KYC">>),
    {ok, _} = cb_exception_queue:enqueue(O3#payment_order.payment_id, <<"Amount">>),
    Reasons = cb_stp_metrics:exception_reasons(),
    %% "Amount" should come first (count = 2)
    [{TopReason, TopCount} | _] = Reasons,
    ?assertEqual(<<"Amount">>, TopReason),
    ?assertEqual(2, TopCount).

sla_compliance_no_resolved(_Config) ->
    Comp = cb_stp_metrics:sla_compliance(),
    ?assertEqual(0, maps:get(total_resolved, Comp)),
    %% No resolved items → perfect compliance by convention
    ?assertEqual(10_000, maps:get(rate_bps, Comp)).

sla_compliance_all_within(_Config) ->
    O1 = write_order(make_order()),
    {ok, Item} = cb_exception_queue:enqueue(O1#payment_order.payment_id, <<"SLA test">>),
    %% Resolve it well before any deadline
    {ok, _} = cb_exception_queue:resolve(Item#exception_item.item_id, approved, <<"OK">>),
    Comp = cb_stp_metrics:sla_compliance(),
    ?assertEqual(1, maps:get(total_resolved, Comp)),
    ?assertEqual(10_000, maps:get(rate_bps, Comp)).

sla_compliance_mixed(_Config) ->
    O1 = write_order(make_order()),
    O2 = write_order(make_order()),
    {ok, I1} = cb_exception_queue:enqueue(O1#payment_order.payment_id, <<"SLA A">>),
    {ok, I2} = cb_exception_queue:enqueue(O2#payment_order.payment_id, <<"SLA B">>),
    %% Set a deadline in the past on I2 before resolving it
    Now = erlang:system_time(millisecond),
    Overdue = I2#exception_item{
        sla_minutes  = 1,
        sla_deadline = Now - 10_000,
        updated_at   = Now
    },
    {atomic, ok} = mnesia:transaction(fun() ->
        mnesia:write(exception_item, Overdue, write)
    end),
    {ok, _} = cb_exception_queue:resolve(I1#exception_item.item_id, approved, <<"OK">>),
    {ok, _} = cb_exception_queue:resolve(I2#exception_item.item_id, rejected, <<"Late">>),
    Comp = cb_stp_metrics:sla_compliance(),
    ?assertEqual(2, maps:get(total_resolved, Comp)),
    ?assertEqual(1, maps:get(within_sla, Comp)).

recent_activity_returns_n_most_recent(_Config) ->
    Orders = [write_order(make_order()) || _ <- lists:seq(1, 5)],
    Activity = cb_stp_metrics:recent_activity(3),
    ?assertEqual(3, length(Activity)),
    %% Each entry has required keys
    lists:foreach(fun(Entry) ->
        ?assert(maps:is_key(payment_id, Entry)),
        ?assert(maps:is_key(amount, Entry)),
        ?assert(maps:is_key(exception_reason, Entry))
    end, Activity),
    _ = Orders.
