-module(cb_streaming_consumers_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").
-include_lib("cb_events/include/cb_events.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([
    register_consumer_ok/1,
    update_cursor_ok/1,
    get_cursor_ok/1,
    get_cursor_not_found/1,
    list_consumers_ok/1,
    replay_from_cursor_ok/1,
    backfill_ok/1
]).

all() ->
    [
        register_consumer_ok,
        update_cursor_ok,
        get_cursor_ok,
        get_cursor_not_found,
        list_consumers_ok,
        replay_from_cursor_ok,
        backfill_ok
    ].

init_per_suite(Config) ->
    mnesia:start(),
    cb_schema:create_tables(),
    {ok, _} = application:ensure_all_started(cb_events),
    Config.

end_per_suite(_Config) ->
    application:stop(cb_events),
    mnesia:stop(),
    ok.

register_consumer_ok(_Config) ->
    {ok, CursorId} = cb_streaming_consumers:register_consumer(<<"consumer-1">>, <<"payment">>),
    ?assert(is_binary(CursorId)).

update_cursor_ok(_Config) ->
    {ok, _} = cb_streaming_consumers:register_consumer(<<"consumer-upd">>, <<"tx">>),
    Now = erlang:system_time(millisecond),
    ok = cb_streaming_consumers:update_cursor(<<"consumer-upd">>, <<"tx">>, Now).

get_cursor_ok(_Config) ->
    {ok, _} = cb_streaming_consumers:register_consumer(<<"consumer-get">>, <<"events">>),
    {ok, Cursor} = cb_streaming_consumers:get_cursor(<<"consumer-get">>, <<"events">>),
    ?assertEqual(<<"consumer-get">>, Cursor#consumer_cursor.consumer_id).

get_cursor_not_found(_Config) ->
    {error, not_found} = cb_streaming_consumers:get_cursor(<<"no-such-consumer">>, <<"topic">>).

list_consumers_ok(_Config) ->
    {ok, _} = cb_streaming_consumers:register_consumer(<<"list-test">>, <<"all">>),
    All = cb_streaming_consumers:list_consumers(),
    ?assert(length(All) >= 1).

replay_from_cursor_ok(_Config) ->
    {ok, _} = cb_streaming_consumers:register_consumer(<<"replay-c">>, <<"payment">>),
    {ok, Events} = cb_streaming_consumers:replay_from_cursor(<<"replay-c">>, <<"payment">>),
    ?assert(is_list(Events)).

backfill_ok(_Config) ->
    Now = erlang:system_time(millisecond),
    {ok, Events} = cb_streaming_consumers:backfill(<<"payment">>, Now - 60000, Now),
    ?assert(is_list(Events)).
