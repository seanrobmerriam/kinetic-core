%% @doc Domain Events Outbox
%%
%% This module implements the domain event outbox pattern for IronLedger.
%% Events are written to the `event_outbox' Mnesia table atomically
%% inside the same transaction that mutates domain records.  A background
%% job (scheduled via cb_jobs) later picks up pending events and drives
%% webhook delivery.
%%
%% <h2>Writing events (inside a Mnesia transaction)</h2>
%%
%% Call `write_outbox/2' from within an active `mnesia:transaction/1' fun:
%%
%% <pre>
%%   Fun = fun() ->
%%       mnesia:write(MyRecord),
%%       cb_events:write_outbox(<<"thing.happened">>, #{id => Id})
%%   end,
%%   mnesia:transaction(Fun)
%% </pre>
%%
%% <h2>Writing events (standalone)</h2>
%%
%% Call `emit/2' from outside any transaction:
%%
%% <pre>
%%   cb_events:emit(<<"thing.happened">>, #{id => Id})
%% </pre>
%%
%% @see cb_webhooks
-module(cb_events).
-behaviour(gen_server).

-include_lib("cb_events/include/cb_events.hrl").

%% Public API
-export([start_link/0, start/0]).
-export([write_outbox/2, emit/2]).
-export([list_events/0, get_event/1, replay_event/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%%--------------------------------------------------------------------
%% Public API
%%--------------------------------------------------------------------

-spec start_link() -> {ok, pid()} | {error, any()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec start() -> {ok, pid()} | {error, any()}.
start() ->
    gen_server:start({local, ?MODULE}, ?MODULE, [], []).

%% @doc Write a domain event inside an active Mnesia transaction.
%%
%% This function must be called from within a `mnesia:transaction/1' fun.
%% It joins the caller's existing transaction and writes the event record
%% atomically alongside whatever domain record the caller is mutating.
%%
%% @param EventType  Binary event type, e.g. `<<"transaction.posted">>'.
%% @param Payload    Arbitrary map of event data.
%% @returns `ok'
-spec write_outbox(binary(), map()) -> binary().
write_outbox(EventType, Payload) when is_binary(EventType), is_map(Payload) ->
    EventId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
    Now = erlang:system_time(millisecond),
    Event = #event_outbox{
        event_id   = EventId,
        event_type = EventType,
        payload    = Payload,
        status     = pending,
        created_at = Now,
        updated_at = Now
    },
    mnesia:write(Event),
    EventId.

%% @doc Emit a domain event outside any transaction.
%%
%% Wraps `write_outbox/2' in its own Mnesia transaction.  Use this
%% from code that is not already inside a transaction.
%%
%% @param EventType  Binary event type.
%% @param Payload    Arbitrary map of event data.
%% @returns `{ok, EventId}' on success.
-spec emit(binary(), map()) -> {ok, binary()} | {error, atom()}.
emit(EventType, Payload) ->
    F = fun() -> write_outbox(EventType, Payload) end,
    case mnesia:transaction(F) of
        {atomic, EventId} -> {ok, EventId};
        {aborted, _}      -> {error, database_error}
    end.

%% @doc List all domain events, newest first.
-spec list_events() -> [#event_outbox{}].
list_events() ->
    F = fun() ->
        mnesia:select(event_outbox, [{#event_outbox{_ = '_'}, [], ['$_']}])
    end,
    case mnesia:transaction(F) of
        {atomic, Events} ->
            lists:sort(fun(A, B) -> A#event_outbox.created_at >= B#event_outbox.created_at end, Events);
        {aborted, _} ->
            []
    end.

%% @doc Get a single domain event by ID.
-spec get_event(binary()) -> {ok, #event_outbox{}} | {error, not_found}.
get_event(EventId) ->
    F = fun() -> mnesia:read(event_outbox, EventId) end,
    case mnesia:transaction(F) of
        {atomic, [Event]} -> {ok, Event};
        {atomic, []}      -> {error, not_found};
        {aborted, _}      -> {error, not_found}
    end.

%% @doc Replay a domain event: reset its status to pending and
%% reschedule webhook delivery.
%%
%% This is an operator action — it allows re-delivery of an event
%% that was previously delivered or failed.  A new set of delivery
%% records will be created for all currently-active subscriptions.
%%
%% @param EventId  The event to replay.
%% @returns `{ok, EventId}' on success, `{error, not_found}' if not found.
-spec replay_event(binary()) -> {ok, binary()} | {error, not_found | database_error}.
replay_event(EventId) ->
    F = fun() ->
        case mnesia:read(event_outbox, EventId) of
            [] ->
                {error, not_found};
            [Event] ->
                Now = erlang:system_time(millisecond),
                mnesia:write(Event#event_outbox{status = pending, updated_at = Now}),
                {ok, EventId}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _}     -> {error, database_error}
    end.

%%--------------------------------------------------------------------
%% gen_server callbacks — the process is a no-op sentinel kept alive
%% so the supervisor tree is healthy.
%%--------------------------------------------------------------------

-spec init([]) -> {ok, #{}}.
init([]) ->
    {ok, #{}}.

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
