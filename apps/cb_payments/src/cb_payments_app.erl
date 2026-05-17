%%%
%% @doc CB Payments Application
%%
%% This is the OTP application callback module for the cb_payments application.
%% It provides the entry point for starting the payments subsystem of Kinetic Core.
%%
%% The cb_payments application is responsible for:
%%
%% <ul>
%%   <li>Processing money transfers between accounts</li>
%%   <li>Handling deposits and withdrawals</li>
%%   <li>Managing transaction reversals</li>
%%   <li>Providing idempotency guarantees for all payment operations</li>
%% </ul>
%%
%% The application starts the cb_payments_sup supervisor, which manages the
%% payment processing workers. Currently, the supervisor runs with no child
%% processes as the payment operations are handled directly via Mnesia.
%%
%% @see cb_payments
%% @see cb_payments_sup

-module(cb_payments_app).
-behaviour(application).

-export([start/2, stop/1, config_change/3]).

%%
%% @doc Start the cb_payments application
%%
%% This function is called by the OTP application framework when starting
%% the cb_payments application. It simply starts the top-level supervisor.
%%
%% @param StartType The type of start (typically <tt>normal</tt>)
%% @param StartArgs Any start arguments (ignored)
%%
%% @returns <tt>{ok, Pid}</tt> of the supervisor, or <tt>{error, Reason}</tt>

-spec start(normal, any()) -> {ok, pid()} | {error, any()}.
start(_StartType, _StartArgs) ->
    cb_payments_sup:start_link().

%%
%% @doc Stop the cb_payments application
%%
%% This function is called by the OTP application framework when stopping
%% the cb_payments application. It performs any necessary cleanup.
%%
%% @param State The application state (ignored)
%%
%% @returns <tt>ok</tt>

-spec stop(any()) -> ok.
stop(_State) ->
    ok.

%%
%% @doc Handle configuration changes
%%
%% This function is called when the application configuration changes at runtime.
%% It allows the application to respond to configuration updates without restart.
%%
%% @param Changed List of changed configuration parameters
%% @param New New configuration values
%% @param Removed List of removed configuration parameters
%%
%% @returns <tt>ok</tt>

-spec config_change(list(), list(), list()) -> ok.
config_change(_Changed, _New, _Removed) ->
    ok.
