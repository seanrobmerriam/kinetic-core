%% @doc Cowboy Middleware for CORS Header Injection
%%
%% This module implements the Cowboy middleware behavior to automatically inject
%% CORS (Cross-Origin Resource Sharing) headers into all HTTP responses.
%%
%% <h2>What is Cowboy Middleware?</h2>
%%
%% Cowboy middleware allows you to process requests and responses at various
%% stages of the HTTP handling pipeline. Middleware functions are called:
%% <ol>
%%   <li>Before routing (cowboy_router)</li>
%%   <li>Before handler execution</li>
%%   <li>After handler execution</li>
%% </ol>
%%
%% This middleware runs after routing but before the final handler, adding
%% CORS headers to every response.
%%
%% <h2>How It Works</h2>
%%
%% <ol>
%%   <li>For every request, CORS headers are added to the response</li>
%%   <li>If the request method is OPTIONS (preflight), immediately return 204</li>
%%   <li>For other methods, continue to the next middleware/handler</li>
%% </ol>
%%
%% The preflight handling is important because browsers send OPTIONS requests
%% to check if the actual cross-origin request is allowed. By responding to
%% OPTIONS with 204 immediately, we avoid unnecessary handler execution.
%%
%% @see cb_cors
%% @see cowboy_middleware
-module(cb_cors_middleware).
-behaviour(cowboy_middleware).

-export([execute/2]).

%% @doc Execute the CORS middleware.
%%
%% This function is called for every HTTP request. It:
%% <ol>
%%   <li>Adds CORS headers to the response</li>
%%   <li>If method is OPTIONS, returns 204 immediately (stops pipeline)</li>
%%   <li>Otherwise, continues to next middleware</li>
%% </ol>
%%
%% @param Req The Cowboy request object
%% @param Env The middleware environment (passed through the pipeline)
%% @returns `{ok, Req, Env}' to continue or `{stop, Req}' to halt
-spec execute(cowboy_req:req(), cowboy_middleware:env()) -> {ok, cowboy_req:req(), cowboy_middleware:env()}.
execute(Req, Env) ->
    Req1 = cowboy_req:set_resp_header(<<"access-control-allow-origin">>, <<"*">>, Req),
    Req2 = cowboy_req:set_resp_header(<<"access-control-allow-methods">>, <<"GET, POST, PUT, PATCH, DELETE, OPTIONS">>, Req1),
    Req3 = cowboy_req:set_resp_header(<<"access-control-allow-headers">>, <<"content-type, authorization">>, Req2),
    
    case cowboy_req:method(Req3) of
        <<"OPTIONS">> ->
            Req4 = cowboy_req:set_resp_header(<<"access-control-max-age">>, <<"86400">>, Req3),
            {stop, cowboy_req:reply(204, #{}, <<>>, Req4)};
        _ ->
            {ok, Req3, Env}
    end.
