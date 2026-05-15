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
    HttpCounters = cb_metrics_counter:get_all(),

    %% Build Prometheus-style text format metrics
    Lines = [
        <<"# HELP erlang_process_count Current number of Erlang processes">>,
        <<"erlang_process_count ">>, integer_to_list(erlang:system_info(process_count)), <<"\n">>,
        <<"# HELP erlang_memory_total_bytes Total memory in bytes">>,
        <<"erlang_memory_total_bytes ">>, integer_to_list(erlang:memory(total)), <<"\n">>,
        <<"# HELP erlang_uptime_ms Node uptime in milliseconds">>,
        <<"erlang_uptime_ms ">>, integer_to_list(WallMs), <<"\n">>,
        <<"# HELP http_requests_total Total HTTP requests">>,
        <<"http_requests_total ">>, integer_to_list(maps:get(http_requests_total, HttpCounters, 0)), <<"\n">>,
        <<"# HELP http_5xx_total Total HTTP 5xx responses">>,
        <<"http_5xx_total ">>, integer_to_list(maps:get(http_5xx_total, HttpCounters, 0)), <<"\n">>
    ],

    MetricsBin = iolist_to_binary(Lines),
    Headers = maps:merge(#{
        <<"content-type">> => <<"text/plain; version=0.0.4; charset=utf-8">>
    }, cb_cors:headers()),
    Req2 = cowboy_req:reply(200, Headers, MetricsBin, Req),
    {ok, Req2, State};
handle(<<"OPTIONS">>, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};
handle(_, Req, State) ->
    {Code, Hdrs, RespBody} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(Code, Hdrs, RespBody, Req),
    {ok, Req2, State}.
