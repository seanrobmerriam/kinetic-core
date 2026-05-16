%% @doc Distributed Tracing and Correlation ID Management
%%
%% This module provides correlation ID generation and propagation for distributed tracing.
%% A correlation ID (also called a trace ID) uniquely identifies a request as it flows
%% through the system, enabling end-to-end tracing and unified logging.
%%
%% <h2>Why Correlation IDs?</h2>
%%
%% In a multi-service system, a single user request often triggers multiple internal
%% operations. Correlation IDs allow us to:
%% <ul>
%%   <li>Track a request across all services and log entries</li>
%%   <li>Identify performance bottlenecks in request chains</li>
%%   <li>Debug issues by correlating logs from different modules</li>
%%   <li>Satisfy audit requirements for financial transactions</li>
%% </ul>
%%
%% <h2>Propagation Strategy</h2>
%%
%% Correlation IDs are propagated in two ways:
%% <ul>
%%   <li><strong>HTTP Headers</strong>: X-Correlation-ID header in HTTP requests/responses</li>
%%   <li><strong>Process Dictionary</strong>: Stored in Erlang process dictionary for in-process access</li>
%% </ul>
%%
%% <h2>Usage Example</h2>
%%
%% In a request handler:
%% ```
%% Handler = fun(Req) ->
%%     CorrelationId = cb_correlation:initialize(Req),
%%     %% ... business logic ...
%%     logger:info(#{correlation_id => CorrelationId, event => my_event})
%% end
%% '''
%%
%% In domain modules called from handlers:
%% ```
%% my_function() ->
%%     CorrelationId = cb_correlation:get(),  %% Fetch from process dictionary
%%     logger:info(#{correlation_id => CorrelationId, event => internal_event})
%% '''
%%
%% @see cb_log_middleware
%% @see logger

-module(cb_correlation).
-compile({no_auto_import, [get/1]}).

-export([
    initialize/1,
    generate_id/0,
    get/0,
    get/1,
    set/1,
    clear/0,
    inject_into_headers/2
]).

-define(CORRELATION_KEY, correlation_id).
-define(CORRELATION_HEADER, <<"x-correlation-id">>).

%% =============================================================================
%% Correlation ID Management
%% =============================================================================

%% @doc Initialize correlation ID for a request.
%%
%% If the request already contains an X-Correlation-ID header (e.g., from an
%% upstream service), use it. Otherwise, generate a new one. Store it in the
%% process dictionary for automatic propagation to all called modules.
%%
%% This function should be called early in the request middleware chain,
%% typically in the logging middleware.
%%
%% @param Req A Cowboy request object
%% @returns The correlation ID (binary)
%%
-spec initialize(cowboy_req:req()) -> binary().
initialize(Req) ->
    CorrelationId = case cowboy_req:header(?CORRELATION_HEADER, Req) of
        undefined ->
            %% No correlation ID from client; generate a new one
            generate_id();
        ClientId ->
            %% Propagate correlation ID from upstream service
            ClientId
    end,
    set(CorrelationId),
    CorrelationId.

%% @doc Generate a new unique correlation ID.
%%
%% Uses UUID v4 to generate a 36-character hex string suitable for
%% correlation across distributed systems.
%%
%% @returns A new correlation ID (binary)
%%
-spec generate_id() -> binary().
generate_id() ->
    uuid:uuid_to_string(uuid:get_v4(), binary_standard).

%% @doc Retrieve the current correlation ID from the process dictionary.
%%
%% Returns the correlation ID associated with the current request.
%% If no correlation ID has been set, returns undefined.
%%
%% This function is typically called from domain modules to include the
%% correlation ID in log entries.
%%
%% @returns The correlation ID (binary), or undefined if not set
%%
-spec get() -> binary() | undefined.
get() ->
    get(?CORRELATION_KEY).

%% @doc Retrieve a value from the process dictionary.
%%
%% Low-level access to the process dictionary. Prefer {@link get/0} for
%% getting the correlation ID.
%%
%% @param Key The key to retrieve
%% @returns The value associated with Key, or undefined if not set
%%
-spec get(atom()) -> any().
get(Key) ->
    erlang:get(Key).

%% @doc Store a correlation ID in the process dictionary.
%%
%% This makes the correlation ID available to all functions called from
%% this process without needing to pass it as a parameter.
%%
%% @param CorrelationId The correlation ID to store (binary)
%% @returns ok
%%
-spec set(binary()) -> ok.
set(CorrelationId) ->
    erlang:put(?CORRELATION_KEY, CorrelationId),
    ok.

%% @doc Clear the correlation ID from the process dictionary.
%%
%% Typically called at the end of request processing to clean up state.
%%
%% @returns ok
%%
-spec clear() -> ok.
clear() ->
    erlang:erase(?CORRELATION_KEY),
    ok.

%% @doc Inject correlation ID into HTTP response headers.
%%
%% Adds the X-Correlation-ID header to the response so that clients
%% can track the request in their own logs.
%%
%% @param Req A Cowboy request object
%% @param CorrelationId The correlation ID to inject
%% @returns Updated Cowboy request object
%%
-spec inject_into_headers(cowboy_req:req(), binary()) -> cowboy_req:req().
inject_into_headers(Req, CorrelationId) ->
    cowboy_req:set_resp_header(?CORRELATION_HEADER, CorrelationId, Req).
