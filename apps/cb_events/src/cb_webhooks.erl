%% @doc Webhook Subscription and Delivery Management
%%
%% This module manages webhook subscriptions and drives event delivery.
%% It is the outbound integration layer: when domain events are emitted
%% to the `event_outbox' table, this module is responsible for matching
%% them to active subscriptions and performing HTTP POST delivery.
%%
%% <h2>Subscription model</h2>
%%
%% Each `webhook_subscription' row maps a callback URL to a single
%% event type (or `<<"*">>' for all types).  A subscriber may register
%% multiple rows if they want to receive several event types at the
%% same URL.
%%
%% <h2>Delivery and retry</h2>
%%
%% `process_pending/0' is called by the `webhook_retry' scheduled job.
%% It picks up all pending events, matches them to active subscriptions,
%% attempts HTTP delivery, and records the outcome in `webhook_delivery'.
%%
%% Deliveries that fail are retried up to `?MAX_ATTEMPTS' times.
%% After that the delivery is marked `dead_letter'.
%%
%% @see cb_events
-module(cb_webhooks).
-behaviour(gen_server).

-include_lib("cb_events/include/cb_events.hrl").

-define(MAX_ATTEMPTS, 3).

%% Public API
-export([start_link/0, start/0]).
-export([create_subscription/2, list_subscriptions/0, get_subscription/1, delete_subscription/1]).
-export([list_deliveries/0, list_deliveries_for_event/1]).
-export([process_pending/0, retry_failed_deliveries/0]).

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

%% @doc Create a webhook subscription.
%%
%% @param CallbackURL  The URL to POST events to.
%% @param EventType    The event type to subscribe to, or `<<"*">>' for all.
%% @returns `{ok, Subscription}' on success.
-spec create_subscription(binary(), binary()) -> {ok, #webhook_subscription{}} | {error, atom()}.
create_subscription(CallbackURL, EventType)
        when is_binary(CallbackURL), is_binary(EventType) ->
    SubId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
    Now = erlang:system_time(millisecond),
    Sub = #webhook_subscription{
        subscription_id = SubId,
        event_type      = EventType,
        callback_url    = CallbackURL,
        status          = active,
        created_at      = Now,
        updated_at      = Now
    },
    F = fun() -> mnesia:write(Sub), {ok, Sub} end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _}     -> {error, database_error}
    end;
create_subscription(_, _) ->
    {error, invalid_parameters}.

%% @doc List all webhook subscriptions.
-spec list_subscriptions() -> [#webhook_subscription{}].
list_subscriptions() ->
    F = fun() ->
        mnesia:select(webhook_subscription, [{#webhook_subscription{_ = '_'}, [], ['$_']}])
    end,
    case mnesia:transaction(F) of
        {atomic, Subs} -> Subs;
        {aborted, _}   -> []
    end.

%% @doc Get a webhook subscription by ID.
-spec get_subscription(binary()) -> {ok, #webhook_subscription{}} | {error, not_found}.
get_subscription(SubId) ->
    F = fun() -> mnesia:read(webhook_subscription, SubId) end,
    case mnesia:transaction(F) of
        {atomic, [Sub]} -> {ok, Sub};
        {atomic, []}    -> {error, not_found};
        {aborted, _}    -> {error, not_found}
    end.

%% @doc Delete a webhook subscription by ID.
-spec delete_subscription(binary()) -> ok | {error, not_found | database_error}.
delete_subscription(SubId) ->
    F = fun() ->
        case mnesia:read(webhook_subscription, SubId) of
            [] -> {error, not_found};
            [_] ->
                mnesia:delete({webhook_subscription, SubId}),
                ok
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _}     -> {error, database_error}
    end.

%% @doc List all webhook delivery records, newest first.
-spec list_deliveries() -> [#webhook_delivery{}].
list_deliveries() ->
    F = fun() ->
        mnesia:select(webhook_delivery, [{#webhook_delivery{_ = '_'}, [], ['$_']}])
    end,
    case mnesia:transaction(F) of
        {atomic, Deliveries} ->
            lists:sort(fun(A, B) -> A#webhook_delivery.created_at >= B#webhook_delivery.created_at end, Deliveries);
        {aborted, _} ->
            []
    end.

%% @doc List delivery records for a specific event.
-spec list_deliveries_for_event(binary()) -> [#webhook_delivery{}].
list_deliveries_for_event(EventId) ->
    F = fun() ->
        mnesia:index_read(webhook_delivery, EventId, event_id)
    end,
    case mnesia:transaction(F) of
        {atomic, Deliveries} -> Deliveries;
        {aborted, _}         -> []
    end.

%% @doc Process all pending events: match to subscriptions and deliver.
%%
%% Called by the `webhook_retry' scheduled job.  Idempotent — events
%% that already have a delivery record for a given subscription are
%% not re-delivered.
%%
%% @returns `ok'
-spec process_pending() -> ok.
process_pending() ->
    Events = list_pending_events(),
    Subscriptions = list_active_subscriptions(),
    lists:foreach(fun(Event) ->
        Matching = matching_subscriptions(Event, Subscriptions),
        lists:foreach(fun(Sub) ->
            deliver_if_needed(Event, Sub)
        end, Matching)
    end, Events),
    ok.

%% @doc Retry all failed (non-dead-letter) deliveries.
%%
%% Called by the `webhook_retry' scheduled job.
%%
%% @returns `ok'
-spec retry_failed_deliveries() -> ok.
retry_failed_deliveries() ->
    process_pending(),
    Deliveries = list_failed_deliveries(),
    lists:foreach(fun(Del) ->
        case Del#webhook_delivery.attempt_status of
            failed ->
                Attempts = Del#webhook_delivery.response_code,
                AttemptCount = case is_integer(Attempts) of
                    true -> Attempts;
                    false -> 0
                end,
                case AttemptCount < ?MAX_ATTEMPTS of
                    true ->
                        case get_event_for_delivery(Del) of
                            {ok, Event} -> attempt_delivery(Event, Del);
                            _           -> ok
                        end;
                    false ->
                        mark_dead_letter(Del)
                end;
            _ ->
                ok
        end
    end, Deliveries),
    ok.

%%--------------------------------------------------------------------
%% Internal helpers
%%--------------------------------------------------------------------

list_pending_events() ->
    F = fun() ->
        mnesia:index_read(event_outbox, pending, status)
    end,
    case mnesia:transaction(F) of
        {atomic, Events} -> Events;
        {aborted, _}     -> []
    end.

list_active_subscriptions() ->
    F = fun() ->
        mnesia:index_read(webhook_subscription, active, status)
    end,
    case mnesia:transaction(F) of
        {atomic, Subs} -> Subs;
        {aborted, _}   -> []
    end.

list_failed_deliveries() ->
    F = fun() ->
        mnesia:index_read(webhook_delivery, failed, attempt_status)
    end,
    case mnesia:transaction(F) of
        {atomic, Dels} -> Dels;
        {aborted, _}   -> []
    end.

matching_subscriptions(Event, Subscriptions) ->
    EventType = Event#event_outbox.event_type,
    lists:filter(fun(Sub) ->
        SubType = Sub#webhook_subscription.event_type,
        SubType =:= <<"*">> orelse SubType =:= EventType
    end, Subscriptions).

deliver_if_needed(Event, Sub) ->
    EventId = Event#event_outbox.event_id,
    SubId   = Sub#webhook_subscription.subscription_id,
    %% Check if a delivery record already exists for this (event, sub) pair
    Existing = list_deliveries_for_event(EventId),
    AlreadyDelivered = lists:any(
        fun(D) -> D#webhook_delivery.subscription_id =:= SubId end,
        Existing
    ),
    case AlreadyDelivered of
        true  -> ok;
        false ->
            DeliveryId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
            Now = erlang:system_time(millisecond),
            Del = #webhook_delivery{
                delivery_id     = DeliveryId,
                subscription_id = SubId,
                event_id        = EventId,
                attempt_status  = pending,
                response_code   = undefined,
                created_at      = Now,
                updated_at      = Now
            },
            persist_delivery(Del),
            attempt_delivery(Event, Del)
    end.

persist_delivery(Del) ->
    F = fun() -> mnesia:write(Del) end,
    mnesia:transaction(F).

attempt_delivery(Event, Del) ->
    Sub = case get_subscription(Del#webhook_delivery.subscription_id) of
        {ok, S} -> S;
        _       -> undefined
    end,
    case Sub of
        undefined -> ok;
        _ ->
            URL     = binary_to_list(Sub#webhook_subscription.callback_url),
            Payload = jsone:encode(event_to_map(Event)),
            Headers = [{"content-type", "application/json"}],
            Req     = {URL, Headers, "application/json", Payload},
            case httpc:request(post, Req, [{timeout, 5000}], []) of
                {ok, {{_, Code, _}, _, _}} when Code >= 200, Code < 300 ->
                    update_delivery_status(Del, delivered, Code);
                {ok, {{_, Code, _}, _, _}} ->
                    update_delivery_status(Del, failed, Code);
                {error, _} ->
                    update_delivery_status(Del, failed, 0)
            end
    end.

update_delivery_status(Del, Status, Code) ->
    Now = erlang:system_time(millisecond),
    Updated = Del#webhook_delivery{
        attempt_status = Status,
        response_code  = Code,
        updated_at     = Now
    },
    F = fun() ->
        mnesia:write(Updated),
        %% If delivered, mark the event as delivered if all its subs are done
        case Status of
            delivered -> maybe_mark_event_delivered(Del#webhook_delivery.event_id);
            _         -> ok
        end
    end,
    mnesia:transaction(F).

maybe_mark_event_delivered(EventId) ->
    Deliveries = mnesia:index_read(webhook_delivery, EventId, event_id),
    AllDone = lists:all(
        fun(D) -> D#webhook_delivery.attempt_status =:= delivered end,
        Deliveries
    ),
    case AllDone andalso Deliveries =/= [] of
        true ->
            case mnesia:read(event_outbox, EventId) of
                [Event] ->
                    Now = erlang:system_time(millisecond),
                    mnesia:write(Event#event_outbox{status = delivered, updated_at = Now});
                [] -> ok
            end;
        false -> ok
    end.

mark_dead_letter(Del) ->
    Now = erlang:system_time(millisecond),
    Updated = Del#webhook_delivery{attempt_status = dead_letter, updated_at = Now},
    F = fun() -> mnesia:write(Updated) end,
    mnesia:transaction(F).

get_event_for_delivery(Del) ->
    cb_events:get_event(Del#webhook_delivery.event_id).

event_to_map(Event) ->
    #{
        <<"event_id">>   => Event#event_outbox.event_id,
        <<"event_type">> => Event#event_outbox.event_type,
        <<"payload">>    => Event#event_outbox.payload,
        <<"created_at">> => Event#event_outbox.created_at
    }.

%%--------------------------------------------------------------------
%% gen_server callbacks
%%--------------------------------------------------------------------

-define(DELIVERY_INTERVAL_MS, 30_000).

-spec init([]) -> {ok, #{}}.
init([]) ->
    {ok, _} = inets:start(httpc, [{profile, cb_webhooks}]),
    erlang:send_after(?DELIVERY_INTERVAL_MS, self(), process_pending),
    {ok, #{}}.

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(process_pending, State) ->
    process_pending(),
    erlang:send_after(?DELIVERY_INTERVAL_MS, self(), process_pending),
    {noreply, State};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    inets:stop(httpc, cb_webhooks),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
