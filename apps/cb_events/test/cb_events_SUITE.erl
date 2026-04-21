-module(cb_events_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_events/include/cb_events.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    emit_event_ok/1,
    list_events_ok/1,
    get_event_ok/1,
    get_event_not_found/1,
    replay_event_ok/1,
    create_subscription_ok/1,
    list_subscriptions_ok/1,
    delete_subscription_ok/1,
    write_outbox_in_transaction/1
]).

all() ->
    [
        emit_event_ok,
        list_events_ok,
        get_event_ok,
        get_event_not_found,
        replay_event_ok,
        create_subscription_ok,
        list_subscriptions_ok,
        delete_subscription_ok,
        write_outbox_in_transaction
    ].

init_per_suite(Config) ->
    mnesia:start(),
    cb_schema:create_tables(),
    {ok, _} = application:ensure_all_started(cb_events),
    Config.

end_per_suite(_Config) ->
    application:stop(cb_events),
    mnesia:stop(),
    mnesia:delete_schema([node()]),
    ok.

init_per_testcase(_TestCase, Config) ->
    lists:foreach(fun(T) -> mnesia:clear_table(T) end,
                  [event_outbox, webhook_subscription, webhook_delivery]),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

%% ===================================================================
%% Tests
%% ===================================================================

emit_event_ok(_Config) ->
    Result = cb_events:emit(<<"test.event">>, #{foo => bar}),
    ?assertMatch({ok, _}, Result).

list_events_ok(_Config) ->
    {ok, _} = cb_events:emit(<<"test.event">>, #{a => 1}),
    {ok, _} = cb_events:emit(<<"test.event">>, #{a => 2}),
    Events = cb_events:list_events(),
    ?assert(length(Events) >= 2).

get_event_ok(_Config) ->
    {ok, EventId} = cb_events:emit(<<"test.event">>, #{key => value}),
    {ok, Event} = cb_events:get_event(EventId),
    ?assertEqual(EventId, Event#event_outbox.event_id),
    ?assertEqual(<<"test.event">>, Event#event_outbox.event_type).

get_event_not_found(_Config) ->
    Result = cb_events:get_event(<<"does-not-exist">>),
    ?assertEqual({error, not_found}, Result).

replay_event_ok(_Config) ->
    {ok, EventId} = cb_events:emit(<<"test.event">>, #{replay => true}),
    Result = cb_events:replay_event(EventId),
    ?assertMatch({ok, _}, Result),
    {ok, Event} = cb_events:get_event(EventId),
    ?assertEqual(pending, Event#event_outbox.status).

create_subscription_ok(_Config) ->
    Result = cb_webhooks:create_subscription(<<"test.event">>, <<"http://localhost/hook">>),
    ?assertMatch({ok, #webhook_subscription{}}, Result).

list_subscriptions_ok(_Config) ->
    {ok, _} = cb_webhooks:create_subscription(<<"a.event">>, <<"http://localhost/hook1">>),
    {ok, _} = cb_webhooks:create_subscription(<<"b.event">>, <<"http://localhost/hook2">>),
    Subs = cb_webhooks:list_subscriptions(),
    ?assert(length(Subs) >= 2).

delete_subscription_ok(_Config) ->
    {ok, Sub} = cb_webhooks:create_subscription(<<"del.event">>, <<"http://localhost/hook">>),
    SubId = Sub#webhook_subscription.subscription_id,
    ok = cb_webhooks:delete_subscription(SubId),
    Subs = cb_webhooks:list_subscriptions(),
    Ids = [S#webhook_subscription.subscription_id || S <- Subs],
    ?assertNot(lists:member(SubId, Ids)).

write_outbox_in_transaction(_Config) ->
    F = fun() ->
        cb_events:write_outbox(<<"txn.test">>, #{amount => 100})
    end,
    {atomic, _} = mnesia:transaction(F),
    Events = cb_events:list_events(),
    Types = [E#event_outbox.event_type || E <- Events],
    ?assert(lists:member(<<"txn.test">>, Types)).
