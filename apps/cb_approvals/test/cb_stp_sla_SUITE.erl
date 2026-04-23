%% @doc CT tests for cb_exception_sla (TASK-052 — SLA and escalation).
-module(cb_stp_sla_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    set_sla_ok/1,
    set_sla_not_found/1,
    check_overdue_empty_when_no_deadlines/1,
    check_overdue_returns_expired_items/1,
    escalate_item_tier1/1,
    escalate_item_tier2/1,
    escalate_already_resolved_fails/1,
    enqueue_with_sla/1
]).

all() ->
    [
        set_sla_ok,
        set_sla_not_found,
        check_overdue_empty_when_no_deadlines,
        check_overdue_returns_expired_items,
        escalate_item_tier1,
        escalate_item_tier2,
        escalate_already_resolved_fails,
        enqueue_with_sla
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
    mnesia:clear_table(exception_item),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

enqueue_item() ->
    PaymentId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
    {ok, Item} = cb_exception_queue:enqueue(PaymentId, <<"Test SLA reason">>),
    Item.

%%% ---------------------------------------------------------------- TESTS ---

set_sla_ok(_Config) ->
    Item = enqueue_item(),
    {ok, Updated} = cb_exception_sla:set_sla(Item#exception_item.item_id, 60),
    ?assertEqual(60, Updated#exception_item.sla_minutes),
    ?assertNotEqual(undefined, Updated#exception_item.sla_deadline).

set_sla_not_found(_Config) ->
    ?assertEqual({error, not_found},
                 cb_exception_sla:set_sla(<<"no-such-id">>, 30)).

check_overdue_empty_when_no_deadlines(_Config) ->
    _Item = enqueue_item(),
    ?assertEqual([], cb_exception_sla:check_overdue()).

check_overdue_returns_expired_items(_Config) ->
    Item = enqueue_item(),
    Id = Item#exception_item.item_id,
    %% Manually set a deadline in the past
    PastDeadline = erlang:system_time(millisecond) - 60_000,
    Expired = Item#exception_item{
        sla_minutes  = 1,
        sla_deadline = PastDeadline
    },
    {atomic, ok} = mnesia:transaction(fun() ->
        mnesia:write(exception_item, Expired, write)
    end),
    Overdue = cb_exception_sla:check_overdue(),
    ?assert(length(Overdue) >= 1),
    Ids = [I#exception_item.item_id || I <- Overdue],
    ?assert(lists:member(Id, Ids)).

escalate_item_tier1(_Config) ->
    Item = enqueue_item(),
    {ok, Esc} = cb_exception_sla:escalate(Item#exception_item.item_id, 1),
    ?assertEqual(escalated, Esc#exception_item.status),
    ?assertEqual(1, Esc#exception_item.escalation_tier).

escalate_item_tier2(_Config) ->
    Item = enqueue_item(),
    {ok, Esc} = cb_exception_sla:escalate(Item#exception_item.item_id, 2),
    ?assertEqual(2, Esc#exception_item.escalation_tier).

escalate_already_resolved_fails(_Config) ->
    Item = enqueue_item(),
    PayId = Item#exception_item.payment_id,
    {ok, _} = cb_exception_queue:resolve(Item#exception_item.item_id,
                                          rejected, <<"Rejected">>),
    ?assertEqual({error, already_resolved},
                 cb_exception_sla:escalate(Item#exception_item.item_id, 1)),
    %% Satisfy dialyzer — PayId was used
    _ = PayId,
    ok.

enqueue_with_sla(_Config) ->
    PaymentId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
    {ok, Item} = cb_exception_queue:enqueue(PaymentId, <<"SLA at enqueue">>, 120),
    ?assertEqual(120, Item#exception_item.sla_minutes),
    ?assertNotEqual(undefined, Item#exception_item.sla_deadline),
    %% Deadline should be roughly 2 hours from now
    Now = erlang:system_time(millisecond),
    ?assert(Item#exception_item.sla_deadline > Now).
