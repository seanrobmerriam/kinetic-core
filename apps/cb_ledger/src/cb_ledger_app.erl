% =============================================================================
% @doc Kinetic Core Application Entry Point
% =============================================================================
%%
%% This module implements the OTP application behavior for the cb_ledger
%% application. It serves as the entry point that starts the application's
%% supervision tree.
%%
%% == Application Responsibilities ==
%%
%% The cb_ledger application is responsible for:
%%
%% - Managing the double-entry ledger database (Mnesia)
%% - Providing the core posting engine for financial transactions
%% - Ensuring ledger integrity through debit/credit validation
%%
%% == Startup Sequence ==
%%
%% When the application starts:
%% 1. The OTP application framework calls `start/2`
%% 2. `start/2` invokes `cb_ledger_sup:start_link()`
%% 3. The supervisor starts and initializes the ledger tables
%%
%% == Dependencies ==
%%
%% cb_ledger has no runtime dependencies on other Kinetic Core applications.
%% However, other applications (cb_accounts, cb_payments) depend on cb_ledger
%% for posting financial transactions.
%%
%% @end
% =============================================================================

-module(cb_ledger_app).
-behaviour(application).

-export([start/2, stop/1]).

%% @doc Starts the cb_ledger application.
%%
%% This function is called by the OTP application framework when starting
%% the cb_ledger application. It delegates to the top-level supervisor
%% to start the application tree.
%%
%% == Parameters ==
%%
%% - `StartType`: The type of start (typically `normal` for production)
%% - `StartArgs`: Arguments passed to the application (typically ignored)
%%
%% == Returns ==
%%
%% - `{ok, Pid}`: Supervisor process ID on successful start
%% - `{error, Reason}`: If startup fails
%%
%% @see cb_ledger_sup
-spec start(normal, any()) -> {ok, pid()} | {error, any()}.
start(_StartType, _StartArgs) ->
    cb_ledger_sup:start_link().

%% @doc Stops the cb_ledger application.
%%
%% This function is called by the OTP application framework when stopping
%% the application. It provides graceful shutdown for the ledger system.
%%
%% == Cleanup ==
%%
%% On shutdown, the application ensures:
%% - All pending Mnesia transactions complete
%% - No partial writes are left in an inconsistent state
%% - The supervisor tree shuts down children in reverse order
%%
%% == Parameters ==
%%
%% - `State`: The application state (unused in this implementation)
%%
%% == Returns ==
%%
%% - `ok`: Shutdown completed successfully
%%
-spec stop(any()) -> ok.
stop(_State) ->
    ok.
