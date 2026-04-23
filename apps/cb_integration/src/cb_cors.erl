%% @doc CORS (Cross-Origin Resource Sharing) Header Management
%%
%% This module provides functions for managing CORS headers in HTTP responses.
%% CORS is a mechanism that allows restricted resources on a web page to be
%% requested from another domain outside the original domain.
%%
%% <h2>What is CORS?</h2>
%%
%% Browsers enforce the "same-origin policy" which blocks JavaScript from making
%% requests to different origins (domain, protocol, or port). CORS extends this
%% by allowing servers to specify who can access their resources and how.
%%
%% <h2>CORS Headers Used</h2>
%%
%% <ul>
%%   <li><b>Access-Control-Allow-Origin</b>: Specifies which origins can access
%%       the resource. Set to "*" to allow all origins (appropriate for public APIs).</li>
%%   <li><b>Access-Control-Allow-Methods</b>: Specifies which HTTP methods are
%%       allowed when accessing the resource.</li>
%%   <li><b>Access-Control-Allow-Headers</b>: Specifies which HTTP headers can be
%%       used during the actual request.</li>
%%   <li><b>Access-Control-Max-Age</b>: Indicates how long the results of a
%%       preflight request can be cached (in seconds).</li>
%% </ul>
%%
%% <h2>Preflight Requests</h2>
%%
%% Browsers send OPTIONS requests (preflight) before making cross-origin requests
%% that might have side effects (POST, PUT, DELETE). The server should respond
%% with appropriate CORS headers and status 204 No Content.
%%
%% @see cb_cors_middleware
-module(cb_cors).
-export([headers/0, reply_preflight/1]).

%% @doc Returns the CORS headers to attach to every response.
%%
%% The headers specify:
%% <ul>
%%   <li>All origins are allowed (*)</li>
%%   <li>GET, POST, PUT, DELETE, OPTIONS methods allowed</li>
%%   <li>Content-Type and Authorization headers allowed in requests</li>
%%   <li>Preflight results cached for 24 hours (86400 seconds)</li>
%% </ul>
%%
%% @returns Map of header names to header values
-spec headers() -> #{<<_:64,_:_*8>> => <<_:8,_:_*16>>}.
headers() ->
    #{
        <<"access-control-allow-origin">>  => <<"*">>,
        <<"access-control-allow-methods">> => <<"GET, POST, PUT, PATCH, DELETE, OPTIONS">>,
        <<"access-control-allow-headers">> => <<"content-type, authorization">>,
        <<"access-control-max-age">>       => <<"86400">>
    }.

%% @doc Respond to an OPTIONS preflight request.
%%
%% When a browser makes a preflight (OPTIONS) request to check CORS permissions,
%% this function returns a 204 No Content response with the appropriate CORS headers.
%%
%% @param Req The Cowboy request object
%% @returns Modified request with 204 response ready to be sent
-spec reply_preflight(cowboy_req:req()) -> cowboy_req:req().
reply_preflight(Req) ->
    cowboy_req:reply(204, headers(), <<>>, Req).
