%% @doc Streaming Consumer Cursor Tracking (TASK-059)
%%
%% Manages per-consumer, per-topic read cursors and provides replay and
%% backfill capabilities over the `event_outbox' table.
%%
%% == Replay ==
%% `replay_from_cursor/2' returns all events for a topic whose `created_at'
%% is greater than the consumer's last acknowledged timestamp.
%%
%% == Backfill ==
%% `backfill/3' returns events in a time range regardless of cursor state.
%% Useful when onboarding a new consumer that needs historical data.
%%
%% == Cursor semantics ==
%% Cursors are keyed by (consumer_id, topic).  Topics are free-form binaries
%% matching the event_type prefix convention (e.g. `<<"payment">>' matches
%% all `<<"payment.*">>` events).
-module(cb_streaming_consumers).

-include_lib("cb_events/include/cb_events.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([register_consumer/2, update_cursor/3, get_cursor/2,
         replay_from_cursor/2, backfill/3, list_consumers/0]).

%%--------------------------------------------------------------------
%% Public API
%%--------------------------------------------------------------------

%% @doc Register a new consumer cursor at the current timestamp.
%%
%% If a cursor already exists for (ConsumerId, Topic) it is left unchanged
%% and the existing cursor_id is returned.
-spec register_consumer(binary(), binary()) ->
    {ok, binary()} | {error, atom()}.
register_consumer(ConsumerId, Topic) ->
    case get_cursor(ConsumerId, Topic) of
        {ok, Existing} ->
            {ok, Existing#consumer_cursor.cursor_id};
        {error, not_found} ->
            CursorId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
            Now      = erlang:system_time(millisecond),
            Record   = #consumer_cursor{
                cursor_id     = CursorId,
                consumer_id   = ConsumerId,
                topic         = Topic,
                last_event_ts = Now,
                updated_at    = Now
            },
            F = fun() -> mnesia:write(Record) end,
            case mnesia:transaction(F) of
                {atomic, ok} -> {ok, CursorId};
                {aborted, _} -> {error, database_error}
            end
    end.

%% @doc Advance a consumer's cursor to the given timestamp.
-spec update_cursor(binary(), binary(), timestamp_ms()) ->
    ok | {error, not_found | database_error}.
update_cursor(ConsumerId, Topic, Timestamp) ->
    case get_cursor(ConsumerId, Topic) of
        {error, not_found} ->
            {error, not_found};
        {ok, Cursor} ->
            Now = erlang:system_time(millisecond),
            Updated = Cursor#consumer_cursor{last_event_ts = Timestamp, updated_at = Now},
            F = fun() -> mnesia:write(Updated) end,
            case mnesia:transaction(F) of
                {atomic, ok} -> ok;
                {aborted, _} -> {error, database_error}
            end
    end.

%% @doc Get the cursor record for a (consumer_id, topic) pair.
-spec get_cursor(binary(), binary()) ->
    {ok, #consumer_cursor{}} | {error, not_found}.
get_cursor(ConsumerId, Topic) ->
    MatchSpec = [{
        #consumer_cursor{cursor_id = '_', consumer_id = ConsumerId,
                         topic = Topic, last_event_ts = '_', updated_at = '_'},
        [], ['$_']
    }],
    case mnesia:dirty_select(consumer_cursor, MatchSpec) of
        [C]     -> {ok, C};
        []      -> {error, not_found};
        [H | _] -> {ok, H}
    end.

%% @doc Return all events for the topic produced after the consumer's cursor.
%%
%% Events are matched on `event_type' prefix — any event whose type starts
%% with Topic or equals Topic is included.
-spec replay_from_cursor(binary(), binary()) ->
    {ok, [#event_outbox{}]} | {error, not_found}.
replay_from_cursor(ConsumerId, Topic) ->
    case get_cursor(ConsumerId, Topic) of
        {error, not_found} ->
            {error, not_found};
        {ok, Cursor} ->
            AfterTs = Cursor#consumer_cursor.last_event_ts,
            Events  = events_for_topic_since(Topic, AfterTs),
            {ok, Events}
    end.

%% @doc Return all events for the topic within [FromTs, ToTs].
%%
%% Does not modify any cursor state.
-spec backfill(binary(), timestamp_ms(), timestamp_ms()) ->
    {ok, [#event_outbox{}]}.
backfill(Topic, FromTs, ToTs) ->
    AllForTopic = events_for_topic_since(Topic, FromTs - 1),
    InRange = [E || E <- AllForTopic, E#event_outbox.created_at =< ToTs],
    {ok, InRange}.

%% @doc List all registered consumer cursors.
-spec list_consumers() -> [#consumer_cursor{}].
list_consumers() ->
    MatchSpec = [{'_', [], ['$_']}],
    mnesia:dirty_select(consumer_cursor, MatchSpec).

%%--------------------------------------------------------------------
%% Internal helpers
%%--------------------------------------------------------------------

-spec events_for_topic_since(binary(), timestamp_ms()) -> [#event_outbox{}].
events_for_topic_since(Topic, AfterTs) ->
    AllEvents = mnesia:dirty_select(event_outbox, [{'_', [], ['$_']}]),
    Filtered  = [E || E <- AllEvents,
                      E#event_outbox.created_at > AfterTs,
                      topic_matches(E#event_outbox.event_type, Topic)],
    lists:sort(fun(A, B) -> A#event_outbox.created_at =< B#event_outbox.created_at end,
               Filtered).

-spec topic_matches(binary(), binary()) -> boolean().
topic_matches(EventType, Topic) ->
    Prefix = <<Topic/binary, ".">>,
    EventType =:= Topic orelse binary:match(EventType, Prefix) =/= nomatch.
