% =============================================================================
% @doc Kinetic Core Top-Level Supervisor
% =============================================================================
%%
%% This module implements the top-level supervisor for the cb_ledger
%% application. It follows the OTP supervisor behavior and is responsible
%% for managing the lifecycle of all child processes within the ledger
%% application.
%%
%% == Supervision Strategy ==
%%
%% The cb_ledger_sup uses the `one_for_one` restart strategy:
%%
%% - If a child process terminates, only that process is restarted
%% - Other child processes continue running unaffected
%% - This is appropriate because ledger operations are independent
%%
%% == Restart Configuration ==
%%
%% - `intensity`: Maximum 5 restarts allowed
%% - `period`: Within 10 seconds
%%
%% If these limits are exceeded, the supervisor terminates, which will
%% cause the entire application to stop. This prevents infinite restart
%% loops in case of persistent failures.
%%
%% == Child Processes ==
%%
%% Currently, the supervisor has no active children. The ledger functionality
%% is primarily provided through the `cb_ledger` module's functions which
%% operate directly on Mnesia tables.
%%
%% Future child processes may include:
%% - Background workers for batch posting
%% - Event handlers for real-time notifications
%% - Mnesia table managers
%%
%% @end
% =============================================================================

-module(cb_ledger_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

%% @doc Starts the cb_ledger supervisor.
%%
%% This function is typically called by the application startup code
%% (cb_ledger_app:start/2) or by the OTP release system.
%%
%% == Registration ==
%%
%% The supervisor is registered locally as `?MODULE` (cb_ledger_sup)
%% using the `local` option, making it accessible via:
%%
%% ```erlang
%% whereis(cb_ledger_sup)
%% ```
%%
%% == Returns ==
%%
%% - `{ok, Pid}`: Supervisor process ID
%% - `{error, Reason}`: If startup fails
%%
%% @see supervisor
-spec start_link() -> {ok, pid()} | {error, any()}.
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% @doc Initializes the supervisor with its child processes.
%%
%% This callback is invoked by the OTP framework when the supervisor
%% starts. It defines the supervision strategy and child specifications.
%%
%% == Supervision Configuration ==
%%
%% ```erlang
%% #{
%%     strategy => one_for_one,  %% Restart only failed child
%%     intensity => 5,           %% Max 5 restarts
%%     period => 10               %% Within 10 seconds
%% }
%% ```
%%
%% == Children ==
%%
%% Currently, no child processes are started. The ledger operations
%% are stateless functions that operate on Mnesia directly.
%%
%% == Returns ==
%%
%% - `{ok, {SupFlags, Children}}`: Supervisor configuration
%%
%% @see supervisor:sup_flags()
%% @see supervisor:child_spec()
-spec init([]) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init([]) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 5,
        period => 10
    },
    Children = [],
    {ok, {SupFlags, Children}}.
