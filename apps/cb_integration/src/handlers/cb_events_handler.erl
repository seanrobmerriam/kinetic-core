%% @doc Events Handler
%%
%% Handler for the `/api/v1/events` and `/api/v1/events/:event_id` endpoints.
%%
%% <h2>REST API Endpoints</h2>
%%
%% <ul>
%%   <li><b>GET /api/v1/events</b> - List all outbox events</li>
%%   <li><b>GET /api/v1/events/:event_id</b> - Get a specific event</li>
%%   <li><b>POST /api/v1/events/:event_id/replay</b> - Replay an event</li>
%% </ul>
%%
%% @see cb_events
-module(cb_events_handler).

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    handle(Method, Req, State).

handle(<<"GET">>, Req, State) ->
    case cowboy_req:binding(event_id, Req) of
        undefined ->
            list_events(Req, State);
        EventId ->
            get_event(EventId, Req, State)
    end;

handle(<<"POST">>, Req, State) ->
    Path = cowboy_req:path(Req),
    case cowboy_req:binding(event_id, Req) of
        undefined ->
            not_found(Req, State);
        EventId ->
            case binary:split(Path, <<"/">>, [global]) of
                [_, <<"api">>, <<"v1">>, <<"events">>, EventId, <<"replay">>] ->
                    replay_event(EventId, Req, State);
                _ ->
                    not_found(Req, State)
            end
    end;

handle(<<"OPTIONS">>, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(405, Headers, <<"{\"error\": \"method_not_allowed\"}">>, Req),
    {ok, Req2, State}.

list_events(Req, State) ->
    Events = cb_events:list_events(),
    Resp = lists:map(fun event_to_map/1, Events),
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req),
    {ok, Req2, State}.

get_event(EventId, Req, State) ->
    case cb_events:get_event(EventId) of
        {ok, Event} ->
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(200, Headers, jsone:encode(event_to_map(Event)), Req),
            {ok, Req2, State};
        {error, Reason} ->
            {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
            Resp = #{error => ErrorAtom, message => Message},
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State}
    end.

replay_event(EventId, Req, State) ->
    case cb_events:replay_event(EventId) of
        {ok, _} ->
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(200, Headers, <<"{\"status\": \"replayed\"}">>, Req),
            {ok, Req2, State};
        {error, Reason} ->
            {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
            Resp = #{error => ErrorAtom, message => Message},
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State}
    end.

not_found(Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(404, Headers, <<"{\"error\": \"not_found\"}">>, Req),
    {ok, Req2, State}.

event_to_map(Event) ->
    #{
        event_id   => element(2, Event),
        event_type => element(3, Event),
        payload    => element(4, Event),
        status     => element(5, Event),
        created_at => element(6, Event),
        updated_at => element(7, Event)
    }.
