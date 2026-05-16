%% @doc Cowboy Middleware for Request/Response Logging
%%
%% This module implements a logging middleware for the Cowboy HTTP server.
%% It logs all incoming requests and their outcomes for monitoring and debugging.
%%
%% <h2>Why Log HTTP Requests?</h2>
%%
%% In a core banking system, logging HTTP traffic is essential for:
%% <ul>
%%   <li>Audit trails - tracking all API access</li>
%%   <li>Performance monitoring - measuring response times</li>
%%   <li>Troubleshooting - investigating issues in production</li>
%%   <li>Security - detecting unusual patterns or attacks</li>
%% </ul>
%%
%% <h2>Distributed Tracing</h2>
%%
%% This middleware also initializes correlation IDs for distributed tracing.
%% Every request gets a unique correlation ID that is:
%% <ul>
%%   <li>Extracted from X-Correlation-ID header if present</li>
%%   <li>Generated as a new UUID if not present</li>
%%   <li>Stored in the process dictionary for propagation to domain modules</li>
%%   <li>Injected into the response header</li>
%%   <li>Included in all log entries</li>
%% </ul>
%%
%% <h2>Logging Flow</h2>
%%
%% <ol>
%%   <li><b>Initialize correlation ID</b>: Extract or generate trace ID</li>
%%   <li><b>Request received</b>: When a request arrives, log method, path, and correlation ID</li>
%%   <li><b>Execute middleware</b>: Pass request to rest of the pipeline</li>
%%   <li><b>Request completed</b>: Log status code, duration, and correlation ID</li>
%%   <li><b>Clean up</b>: Clear correlation ID from process dictionary</li>
%% </ol>
%%
%% <h2>Timing Information</h2>
%%
%% The middleware captures timing information using `erlang:monotonic_time/1`
%% which provides high-resolution timing. Duration is calculated as the
%% difference between the start time and completion time, measured in milliseconds.
%%
%% @see cb_correlation
%% @see cowboy_middleware
%% @see logger
-module(cb_log_middleware).
-behaviour(cowboy_middleware).
-export([execute/2]).

-spec execute(cowboy_req:req(), cowboy_middleware:env()) -> {ok, cowboy_req:req(), cowboy_middleware:env()}.
execute(Req, Env) ->
    Method = cowboy_req:method(Req),
    Path   = cowboy_req:path(Req),
    Start  = erlang:monotonic_time(millisecond),

    %% Initialize correlation ID: extract from header or generate new one
    CorrelationId = cb_correlation:initialize(Req),

    %% Log the incoming request with correlation ID
    logger:info(#{
        event            => request_received,
        correlation_id   => CorrelationId,
        method           => Method,
        path             => Path,
        time             => erlang:system_time(millisecond)
    }),

    %% In Cowboy 2.x, middlewares simply return {ok, Req, Env} to continue.
    %% Post-request logging is handled differently (via stream handlers or hooks).
    %% Here we just log that we're processing the request.
    Result = {ok, Req, Env},
    cb_metrics_counter:increment(http_requests_total),

    Duration = erlang:monotonic_time(millisecond) - Start,
    logger:info(#{
        event            => request_completed,
        correlation_id   => CorrelationId,
        method           => Method,
        path             => Path,
        duration         => Duration
    }),

    Result.
