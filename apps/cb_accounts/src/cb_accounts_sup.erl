%%%
%% @doc cb_accounts_sup - Top-Level Supervisor
%%
%% This module implements the OTP {@link supervisor} behaviour and serves as
%% the top-level supervisor for the cb_accounts application in Kinetic Core.
%%
%% h2. Supervision Role
%%
%% The supervisor is responsible for starting, stopping, and managing all
%% child processes within the cb_accounts application. It implements the
%% fault-tolerant supervision tree pattern that is fundamental to OTP applications.
%%
%% h2. Supervision Strategy
%%
%% This supervisor uses the <strong>one_for_one</strong> restart strategy:
%% <ul>
%%   <li>If a child process terminates, only that specific process is restarted</li>
%%   <li>Other child processes continue running unaffected</li>
%%   <li>Suited for independent workers that don't have dependencies on each other</li>
%% </ul>
%%
%% h2. Restart Intensity
%%
%% The supervisor is configured with:
%% <ul>
%%   <li><strong>intensity = 5</strong>: Maximum 5 restarts allowed</li>
%%   <li><strong>period = 10</strong> - Within a 10-second window</li>
%% </ul>
%%
%% If these limits are exceeded, the supervisor will terminate all children
%% and exit, allowing higher-level supervisors to handle the failure.
%%
%% h2. Child Processes
%%
%% Currently, this supervisor manages no persistent child processes.
%% All account operations are performed via the {@link cb_accounts} module
%% which executes within transient Mnesia transactions. This design is
%% appropriate because:
%% <ul>
%%   <li>Account data is stored in Mnesia (distributed database)</li>
%%   <li>No long-running background workers are needed</li>
%%   <li>Each operation is self-contained in a transaction</li>
%% </ul>
%%
%% The supervisor exists to satisfy OTP application requirements and to
%% provide a foundation for future child processes if needed (e.g.,
%% background balance synchronization, event processors, etc.).
%%
%% h2. Supervision Tree Position
%%
%% <pre>
%% cb_integration_sup (root)
%%   └── cb_accounts_sup (this module)
%% </pre>
%%
%% This supervisor is started as a child of the main application supervisor.
%% If cb_accounts_sup terminates, it will signal its parent supervisor
%% according to the restart intensity settings.
%%
%% @see supervisor
%% @see cb_accounts_app
%% @see cb_accounts

-module(cb_accounts_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

%% =============================================================================
%% Supervisor Exports
%% =============================================================================

%% @doc Starts the cb_accounts_sup supervisor and links it to the calling process.
%%
%% This function is typically called by the application callback module
%% ({@link cb_accounts_app:start/2}) during application startup. It registers
%% the supervisor locally with the name `?MODULE` (cb_accounts_sup) and
%% initializes the supervision tree.
%%
%% h4. Registration
%% <ul>
%%   <li>Registered locally as `cb_accounts_sup`</li>
%%   <li>Part of the Kinetic Core supervision hierarchy</li>
%% </ul>
%%
%% @returns {@type {ok, pid()}} if the supervisor starts successfully,
%%          {@type {error, {already_started, pid()}}} if already running,
%%          {@type {error, term()} for other failures
%%
-spec start_link() -> {ok, pid()} | {error, any()}.
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% @private Initializes the supervisor with its child specifications.
%%
%% This callback is called by the OTP supervisor framework when the
%% supervisor starts. It defines:
%% <ul>
%%   <li>The supervision strategy (one_for_one)</li>
%%   <li>Restart intensity limits</li>
%%   <li>Child process specifications</li>
%% </ul>
%%
%% h4. Child Specifications
%%
%% Currently, the children list is empty `[]`. This is intentional because
%% cb_accounts operates in a stateless manner using Mnesia transactions.
%% Each account operation is a self-contained transaction that completes
%% without requiring a persistent background process.
%%
%% If future requirements introduce long-running workers (e.g., scheduled
%% balance checks, event listeners), they would be added to this list.
%%
%% @param _Args Arguments passed from start_link (ignored)
%% @returns {@type {ok, {supervisor_flags(), [child_spec()]}}}
%%          containing supervisor flags and empty child list
%%
-spec init([]) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init([]) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 5,
        period => 10
    },
    Children = [],
    {ok, {SupFlags, Children}}.
