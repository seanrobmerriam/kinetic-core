%% @doc Metrics handler for Erlang VM and application telemetry.
%%
%% Returns a JSON object with key runtime metrics from the Erlang VM.
%% This endpoint is public (no authentication required) and exempt from
%% rate limiting so that monitoring agents can always reach it.
%%
%% GET /metrics
%% Response 200 application/json:
%%   {
%%     "process_count": <integer>,   – current Erlang process count
%%     "memory_total":  <integer>,   – total memory in bytes
%%     "uptime_ms":     <integer>    – node uptime in milliseconds
%%   }
-module(cb_metrics_handler).

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    handle(Method, Req, State).

handle(<<"GET">>, Req, State) ->
    {WallMs, _} = erlang:statistics(wall_clock),
    Metrics = #{
        process_count => erlang:system_info(process_count),
        memory_total  => erlang:memory(total),
        uptime_ms     => WallMs
    },
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(200, Headers, jsone:encode(Metrics), Req),
    {ok, Req2, State};
handle(<<"OPTIONS">>, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};
handle(_, Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(405, Headers, <<"{\"error\":\"method_not_allowed\"}">>, Req),
    {ok, Req2, State}.
