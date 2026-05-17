%%%
%%% @doc Savings Products Application Module.
%%%
%%% This module implements the OTP application behaviour for the
%%% cb_savings_products application.
%%%
%%% ## Application Purpose
%%%
%%% The cb_savings_products application manages the lifecycle of
%%% savings product definitions in the Kinetic Core core banking system.
%%% It provides the foundation for opening and managing interest-bearing
%%% savings accounts.
%%%
%%% ## Application Dependencies
%%%
%%% <ul>
%%%   <li>cb_ledger - For posting interest transactions</li>
%%%   <li>cb_interest - For calculating and accruing interest</li>
%%% </ul>
%%%
%%% ## Supervision Tree
%%%
%%% This application starts a top-level supervisor (`cb_savings_products_sup`)
%%% which manages any child processes required by the savings products module.
%%% Currently, no persistent child processes are required as all operations
%%% are stateless and use Mnesia directly.
%%%
%%% @see cb_savings_products
%%% @see cb_savings_products_sup
%%% @see savings_product.hrl

-module(cb_savings_products_app).
-behaviour(application).

-export([start/2, stop/1]).

%%%
%%% @doc Starts the savings products application.
%%%
%%% Called by the OTP application controller when starting the application.
%%% This function starts the top-level supervisor for the application.
%%%
%%% @param StartType The type of startup (typically `normal` for production)
%%% @param StartArgs Arguments passed to the application (typically ignored)
%%%
%%% @returns `{ok, Pid}' where Pid is the supervisor process
%%% @returns `{error, Reason}' if startup fails
%%%
-spec start(StartType :: normal, StartArgs :: any()) ->
    {ok, pid()} | {error, any()}.
start(_StartType, _StartArgs) ->
    cb_savings_products_sup:start_link().

%%%
%%% @doc Stops the savings products application.
%%%
%%% Called by the OTP application controller when stopping the application.
%%% Performs any necessary cleanup. As this application uses transient
%%% processes via Mnesia, no explicit cleanup is required.
%%%
%%% @param State The application state (unused)
%%%
%%% @returns `ok'
%%%
-spec stop(State :: any()) -> ok.
stop(_State) ->
    ok.
