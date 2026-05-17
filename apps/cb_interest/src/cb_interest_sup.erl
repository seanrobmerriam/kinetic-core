%%%
%%% @doc Top-level supervisor for the Kinetic Core interest application.
%%%
%%% This module implements the OTP supervisor behaviour for the cb_interest application.
%%% It is the root of the process supervision tree and is responsible for starting
%%% and managing all child processes within the interest subsystem.
%%%
%%% == Supervision Strategy ==
%%%
%%% This supervisor uses the `one_for_one` restart strategy:
%%% <ul>
%%% <li><b>one_for_one</b>: If a child process terminates, only that process is restarted.
%%%     Other child processes continue running unaffected.</li>
%%% </ul>
%%%
%%% The intensity and period settings (5 restarts per 10 seconds) provide protection
%%% against rapid crash loops while allowing legitimate temporary failures.
%%%
%%% == Child Processes ==
%%%
%%% Currently, this supervisor starts with no child processes. The interest calculation
%%% and accrual functions are invoked directly by other applications (such as batch
%%% jobs or account operations) rather than running as persistent background workers.
%%%
%%% Future enhancements may add:
%%% <ul>
%%% <li>Periodic scheduler for daily interest accrual processing</li>
%%% <li>Interest posting worker pool for batch operations</li>
%%% <li>Accrual state cache for performance optimization</li>
%%% </ul>
%%%
-module(cb_interest_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

%%%
%%% @doc Start the cb_interest_sup supervisor.
%%%
%%% Registers the supervisor locally with the name 'cb_interest_sup' and initializes
%%% the supervision tree.
%%%
%%% @returns {ok, Pid} on success, {error, Reason} on failure
%%%
-spec start_link() -> {ok, pid()} | {error, any()}.
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%%%
%%% @doc Initialize the supervisor with its child specifications.
%%%
%%% This function is called by the supervisor to set up the child process tree.
%%% It defines the restart strategy and any child processes to start.
%%%
%%% @param [] Initialization arguments (unused)
%%% @returns {ok, {SupFlags, Children}} where SupFlags defines the strategy
%%%          and Children is the list of child specifications
%%%
-spec init([]) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init([]) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 5,
        period => 10
    },
    Children = [],
    {ok, {SupFlags, Children}}.
