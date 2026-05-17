%%%
%%% @doc OTP Application callback for the Kinetic Core interest application.
%%%
%%% This module implements the OTP application behaviour for the cb_interest
%%% application. It is the entry point for starting the interest subsystem when
%%% the Kinetic Core node boots.
%%%
%%% == Application Responsibilities ==
%%%
%%% The cb_interest application is responsible for:
%%% <ul>
%%% <li>Managing interest calculation for savings and loan products</li>
%%% <li>Tracking interest accruals on accounts</li>
%%% <li>Posting accrued interest to the general ledger</li>
%%% </ul>
%%%
%%% This application depends on:
%%% <ul>
%%% <li>cb_ledger - for posting interest entries to accounts</li>
%%% <li>cb_accounts - for account information and balance queries</li>
%%% </ul>
%%%
%%% == Startup Process ==
%%%
%%% When the application starts, it:
%%% <ol>
%%% <li>Starts the top-level supervisor (cb_interest_sup)</li>
%%% <li>The supervisor initializes child processes if any are defined</li>
%%% </ol>
%%%
-module(cb_interest_app).
-behaviour(application).

-export([start/2, stop/1]).

%%%
%%% @doc Start the cb_interest application.
%%%
%%% This function is called by the OTP runtime when starting the application.
%%% It delegates to the top-level supervisor to start the application process tree.
%%%
%%% @param StartType The type of startup (typically 'normal')
%%% @param StartArgs Arguments passed to the application start
%%% @returns {ok, Pid} of the top-level supervisor on success
%%%
-spec start(normal, any()) -> {ok, pid()} | {error, any()}.
start(_StartType, _StartArgs) ->
    cb_interest_sup:start_link().

%%%
%%% @doc Stop the cb_interest application.
%%%
%%% This function is called by the OTP runtime when stopping the application.
%%% It performs cleanup operations before the application terminates.
%%%
%%% @param State The application state from start/2
%%% @returns ok
%%%
-spec stop(any()) -> ok.
stop(_State) ->
    ok.
