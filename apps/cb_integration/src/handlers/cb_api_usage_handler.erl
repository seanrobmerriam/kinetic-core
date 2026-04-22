%% @doc API Usage Handler
%%
%% GET /api/v1/api-keys/:key_id/usage
%%
%% Returns all recorded usage events for the given API key, newest first.
-module(cb_api_usage_handler).

-export([init/2]).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    handle(Method, Req, State).

handle(<<"GET">>, Req, State) ->
    KeyId = cowboy_req:binding(key_id, Req),
    Events = cb_api_usage:get_usage_for_key(KeyId),
    Resp = lists:map(fun event_to_map/1, Events),
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req),
    {ok, Req2, State};

handle(<<"OPTIONS">>, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(405, Headers, <<"{\"error\": \"method_not_allowed\"}">>, Req),
    {ok, Req2, State}.

event_to_map(E) ->
    #{
        event_id    => E#api_usage_event.event_id,
        key_id      => E#api_usage_event.key_id,
        method      => E#api_usage_event.method,
        path        => E#api_usage_event.path,
        recorded_at => E#api_usage_event.recorded_at
    }.
