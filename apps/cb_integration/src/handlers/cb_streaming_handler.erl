%% @doc HTTP handler for streaming consumer cursors (TASK-059).
%%
%% Routes:
%%   GET  /api/v1/streams/consumers                          — list consumers
%%   POST /api/v1/streams/consumers                          — register consumer
%%   GET  /api/v1/streams/consumers/:consumer_id/replay      — replay from cursor
%%   POST /api/v1/streams/consumers/:consumer_id/cursor      — advance cursor
%%   GET  /api/v1/streams/backfill                           — backfill by topic/range
-module(cb_streaming_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").
-include_lib("cb_events/include/cb_events.hrl").

-export([init/2]).

init(Req, State) ->
    Method     = cowboy_req:method(Req),
    ConsumerId = cowboy_req:binding(consumer_id, Req),
    Action     = cowboy_req:binding(action, Req),
    handle(Method, ConsumerId, Action, Req, State).

handle(<<"GET">>, undefined, undefined, Req, State) ->
    Consumers = cb_streaming_consumers:list_consumers(),
    Req2 = cowboy_req:reply(200, headers(),
               jsone:encode(#{consumers => [cursor_to_map(C) || C <- Consumers]}), Req),
    {ok, Req2, State};

handle(<<"POST">>, undefined, undefined, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{consumer_id := ConsumerId, topic := Topic}, _} ->
            case cb_streaming_consumers:register_consumer(ConsumerId, Topic) of
                {ok, CursorId} ->
                    Req3 = cowboy_req:reply(201, headers(),
                               jsone:encode(#{cursor_id => CursorId}), Req2),
                    {ok, Req3, State};
                {error, Reason} ->
                    error_reply(500, Reason, Req2, State)
            end;
        _ ->
            error_reply(400, <<"Missing required fields: consumer_id, topic">>, Req2, State)
    end;

handle(<<"GET">>, ConsumerId, <<"replay">>, Req, State) ->
    QS     = cowboy_req:parse_qs(Req),
    Topic  = proplists:get_value(<<"topic">>, QS, <<>>),
    case cb_streaming_consumers:replay_from_cursor(ConsumerId, Topic) of
        {ok, Events} ->
            Req2 = cowboy_req:reply(200, headers(),
                       jsone:encode(#{events => [event_to_map(E) || E <- Events]}), Req),
            {ok, Req2, State};
        {error, not_found} ->
            error_reply(404, <<"Consumer cursor not found">>, Req, State)
    end;

handle(<<"POST">>, ConsumerId, <<"cursor">>, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{topic := Topic, last_event_ts := Ts}, _} ->
            case cb_streaming_consumers:update_cursor(ConsumerId, Topic, Ts) of
                ok ->
                    Req3 = cowboy_req:reply(200, headers(),
                               jsone:encode(#{status => <<"updated">>}), Req2),
                    {ok, Req3, State};
                {error, Reason} ->
                    error_reply(400, Reason, Req2, State)
            end;
        _ ->
            error_reply(400, <<"Missing required fields: topic, last_event_ts">>, Req2, State)
    end;

handle(<<"GET">>, <<"backfill">>, undefined, Req, State) ->
    QS     = cowboy_req:parse_qs(Req),
    Topic  = proplists:get_value(<<"topic">>, QS, <<>>),
    FromTs = binary_to_integer(proplists:get_value(<<"from_ts">>, QS, <<"0">>)),
    ToTs   = binary_to_integer(proplists:get_value(<<"to_ts">>, QS, integer_to_binary(erlang:system_time(millisecond)))),
    case cb_streaming_consumers:backfill(Topic, FromTs, ToTs) of
        {ok, Events} ->
            Req2 = cowboy_req:reply(200, headers(),
                       jsone:encode(#{events => [event_to_map(E) || E <- Events]}), Req),
            {ok, Req2, State}
    end;

handle(_Method, _ConsumerId, _Action, Req, State) ->
    error_reply(405, <<"Method not allowed">>, Req, State).

%%--------------------------------------------------------------------
%% Helpers
%%--------------------------------------------------------------------

cursor_to_map(C) ->
    #{cursor_id     => C#consumer_cursor.cursor_id,
      consumer_id   => C#consumer_cursor.consumer_id,
      topic         => C#consumer_cursor.topic,
      last_event_ts => C#consumer_cursor.last_event_ts,
      updated_at    => C#consumer_cursor.updated_at}.

event_to_map(E) ->
    #{event_id   => E#event_outbox.event_id,
      event_type => E#event_outbox.event_type,
      payload    => E#event_outbox.payload,
      status     => E#event_outbox.status,
      created_at => E#event_outbox.created_at}.

headers() ->
    #{<<"content-type">> => <<"application/json">>}.

error_reply(Code, Reason, Req, State) when is_atom(Reason) ->
    error_reply(Code, atom_to_binary(Reason, utf8), Req, State);
error_reply(Code, Reason, Req, State) ->
    Req2 = cowboy_req:reply(Code, headers(),
               jsone:encode(#{error => Reason}), Req),
    {ok, Req2, State}.
