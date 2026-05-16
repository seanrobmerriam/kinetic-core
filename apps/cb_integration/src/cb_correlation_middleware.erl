%% @doc Cowboy Middleware for Correlation ID Response Header Injection
%%
%% This middleware injects the X-Correlation-ID header into all HTTP responses,
%% enabling clients to track requests across service boundaries.
%%
%% <h2>Purpose</h2>
%%
%% When a client receives an error or needs to report a problem, they can provide
%% the correlation ID from the response header. This allows support teams to search
%% logs for that ID to understand what happened on the server side.
%%
%% <h2>Placement in Middleware Chain</h2>
%%
%% This middleware should run near the end of the middleware chain, after:
%% - Logging (to ensure correlation ID is available)
%% - Authentication and authorization
%% - Request validation
%%
%% Typically placed before the handler execution.
%%
%% @see cb_correlation
%% @see cb_log_middleware
%% @see cowboy_middleware

-module(cb_correlation_middleware).
-behaviour(cowboy_middleware).

-export([execute/2]).

%% @doc Execute the correlation ID response header injection middleware.
%%
%% Retrieves the correlation ID from the process dictionary (set by cb_log_middleware)
%% and injects it into the response header if a correlation ID exists.
%%
%% @param Req The Cowboy request object
%% @param Env The middleware environment (passed through the pipeline)
%% @returns `{ok, Req, Env}' to continue to next middleware
%%
-spec execute(cowboy_req:req(), cowboy_middleware:env()) -> {ok, cowboy_req:req(), cowboy_middleware:env()}.
execute(Req, Env) ->
    %% Retrieve correlation ID from process dictionary
    case cb_correlation:get() of
        undefined ->
            %% No correlation ID set (shouldn't happen if log middleware is in place)
            {ok, Req, Env};
        CorrelationId ->
            %% Inject correlation ID into response headers
            Req1 = cb_correlation:inject_into_headers(Req, CorrelationId),
            {ok, Req1, Env}
    end.
