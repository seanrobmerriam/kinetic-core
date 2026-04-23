%% @doc IronLedger HTTP API Application
%%
%% This module is the main entry point for the cb_integration OTP application.
%% It implements the `application` behaviour and is responsible for:
%%
%% <ul>
%%   <li>Initializing Mnesia database schema</li>
%%   <li>Starting the Cowboy HTTP server</li>
%%   <li>Setting up routing and middleware chains</li>
%% </ul>
%%
%% The application starts a Cowboy HTTP server on a configurable port (default 8080).
%% Cowboy is a small, fast, modular HTTP server built in Erlang. It provides:
%%
%% <ul>
%%   <li>A REST-oriented request handler model</li>
%%   <li>Middleware pipeline for request/response processing</li>
%%   <li>Routing based on host, path, and HTTP method</li>
%% </ul>
%%
%% The HTTP server is started with the following middleware stack (in order):
%%
%% <ol>
%%   <li>`cowboy_router` - Matches incoming requests to handlers based on path</li>
%%   <li>`cb_log_middleware` - Logs all incoming requests and their responses</li>
%%   <li>`cb_cors_middleware` - Adds CORS headers for cross-origin requests</li>
%%   <li>`cowboy_handler` - Dispatches to the matched handler module</li>
%% </ol>
%%
%% On shutdown, the application gracefully stops the Cowboy listener.
%%
%% @see cowboy
%% @see cb_router
%% @see cb_schema
-module(cb_integration_app).
-behaviour(application).

-export([start/2, stop/1]).

%% @doc Start the application and all its dependencies.
%%
%% This function is called by the OTP runtime when the application is started.
%% It performs the following steps:
%%
%% <ol>
%%   <li>Creates Mnesia schema on the current node (if not already present)</li>
%%   <li>Starts the Mnesia database</li>
%%   <li>Creates all required database tables (party, account, transaction, ledger_entry)</li>
%%   <li>Retrieves HTTP configuration (port and number of acceptors) from application env</li>
%%   <li>Compiles the Cowboy dispatch rules from cb_router</li>
%%   <li>Starts the Cowboy HTTP server with configured middleware</li>
%%   <li>Starts the application supervisor</li>
%% </ol>
%%
%% The HTTP port is read from `cb_integration` application environment as `http_port`.
%% The number of acceptor processes is read as `http_acceptors`. These can be
%% configured in `config/sys.config`.
%%
%% @param _StartType Identifies the type of start (typically 'normal' for production)
%% @param _StartArgs Arguments passed to the application (typically empty)
%% @returns `{ok, Pid}' on successful startup, `{error, Reason}' on failure
-spec start(normal, any()) -> {ok, pid()} | {error, any()}.
start(_StartType, _StartArgs) ->
    %% Create Mnesia schema and start Mnesia
    case mnesia:create_schema([node()]) of
        ok -> ok;
        {error, {_, {already_exists, _}}} -> ok
    end,
    ok = mnesia:start(),

    %% Create tables
    ok = cb_schema:create_tables(),
    ok = cb_metrics_counter:init(),
    ok = cb_auth:ensure_bootstrap_users(),

    %% Start Cowboy HTTP server
    {ok, Port} = application:get_env(cb_integration, http_port),
    {ok, Acceptors} = application:get_env(cb_integration, http_acceptors),

    Dispatch = cb_router:dispatch(),
    {ok, _} = cowboy:start_clear(
        ironledger_http,
        [{port, Port}, {num_acceptors, Acceptors}],
        #{
            env => #{dispatch => Dispatch},
            middlewares => [cowboy_router, cb_log_middleware, cb_cors_middleware, cb_version_middleware, cb_rate_limit_middleware, cb_auth_middleware, cb_deprecation_middleware, cowboy_handler]
        }
    ),

    cb_integration_sup:start_link().

%% @doc Stop the application and clean up resources.
%%
%% Called when the application is stopped. This function:
%%
%% <ol>
%%   <li>Stops the Cowboy HTTP listener (ironledger_http)</li>
%%   <li>Mnesia will be stopped automatically by the Erlang VM on shutdown</li>
%% </ol>
%%
%% @param _State The application state (unused in this implementation)
%% @returns `ok' always
-spec stop(any()) -> ok.
stop(_State) ->
    case cowboy:stop_listener(ironledger_http) of
        ok -> ok;
        {error, not_found} -> ok
    end.
