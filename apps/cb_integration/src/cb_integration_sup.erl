%% @doc IronLedger Application Supervisor
%%
%% This module implements the top-level supervisor for the cb_integration
%% application. It follows the OTP supervisor behaviour and provides fault
%% tolerance for the HTTP API layer.
%%
%% In IronLedger's architecture, this supervisor manages no child processes directly.
%% The actual HTTP server (Cowboy) is started by the application callback module
%% (cb_integration_app) rather than under this supervisor. This is intentional because:
%%
%% <ul>
%%   <li>Cowboy has its own internal process management and supervision</li>
%%   <li>The application callback is the natural place to start transient services</li>
%%   <li>Keeping the supervisor empty provides a clear restart boundary</li>
%% </ul>
%%
%% If child processes need to be added in the future (e.g., for background workers,
%% notification services, or additional HTTP listeners), they can be added to the
%% `Children' list in the `init/1' function.
%%
%% The supervisor uses a `one_for_one' restart strategy with the following parameters:
%%
%% <ul>
%%   <li>`intensity' = 5: Maximum 5 restarts within 10 seconds before permanent failure</li>
%%   <li>`period' = 10: The time window for counting restarts (in seconds)</li>
%% </ul>
%%
%% @see supervisor
%% @see cb_integration_app
-module(cb_integration_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

%% @doc Start the application supervisor.
%%
%% This function registers the supervisor locally with the name `cb_integration_sup'
%% and initializes it with the configuration from `init/1'.
%%
%% @returns `{ok, Pid}' on successful startup, `{error, Reason}' on failure
-spec start_link() -> {ok, pid()} | {error, any()}.
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% @doc Initialize the supervisor with empty children.
%%
%% Called by the OTP framework when the supervisor starts. Returns the supervisor
%% flags and an empty child list, as no child processes are managed by this supervisor.
%%
%% The supervisor configuration uses `one_for_one' strategy, which means if a child
%% process terminates, only that process is restarted - other children continue unaffected.
%% This is appropriate for independent workers with no interdependencies.
%%
%% @param _Args Arguments passed to start_link (unused)
%% @returns `{ok, {SupFlags, Children}}' where SupFlags defines restart strategy
%%          and Children is the list of child specifications (empty in this case)
-spec init([]) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init([]) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 5,
        period => 10
    },
    Children = [
        #{
            id      => cb_rate_limiter,
            start   => {cb_rate_limiter, start_link, []},
            restart => permanent,
            type    => worker,
            modules => [cb_rate_limiter]
        }
    ],
    {ok, {SupFlags, Children}}.
