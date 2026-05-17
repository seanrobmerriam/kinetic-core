%%%===================================================================
%%%
%%% @doc Loan Application Module
%%%
%%% This is the OTP application callback module for the cb_loans
%%% application. It provides the entry point for starting the
%%% loan management subsystem.
%%%
%%% <h2>Application Overview</h2>
%%%
%%% The cb_loans application manages all loan-related functionality
%%% including loan products, loan accounts, and repayment processing.
%%% It is started as part of the Kinetic Core banking platform.
%%%
%%% <h2>Supervision Tree</h2>
%%%
%%% <pre>
%%% cb_loans_sup
%%%   ├── cb_loan_products
%%%   ├── cb_loan_accounts
%%%   └── cb_loan_repayments
%%% </pre>
%%%
%%% @end
%%%===================================================================

-module(cb_loans_app).
-behaviour(application).

-export([start/2, stop/1, config_change/3]).

%%
%% @doc Starts the cb_loans application.
%%
%% Called by the OTP runtime when starting the application.
%% Delegates to the supervisor to start the child processes.
%%
%% @param StartType normal | takeover | fail
%% @param StartArgs Arguments passed to start (ignored)
%%
%% @returns {ok, pid()} on success, {error, term()} on failure
%%
-spec start(normal, any()) -> {ok, pid()} | {error, any()}.
start(_StartType, _StartArgs) ->
    cb_loans_sup:start_link().

%%
%% @doc Stops the cb_loans application.
%%
%% Called by the OTP runtime when stopping the application.
%% Performs cleanup of any application-specific resources.
%%
%% @param State Application state from start/2
%%
%% @returns ok
%%
-spec stop(any()) -> ok.
stop(_State) ->
    ok.

%%
%% @doc Handles configuration changes.
%%
%% Called when application configuration is changed at runtime.
%% Allows the application to respond to config updates.
%%
%% @param Changed List of changed config parameters
%% @param New List of new config parameters
%% @param Removed List of removed config parameters
%%
%% @returns ok
%%
-spec config_change(list(), list(), list()) -> ok.
config_change(_Changed, _New, _Removed) ->
    ok.
