%%%
%% @doc cb_accounts_app - OTP Application Callback Module
%%
%% This module implements the OTP {@link application} behaviour and serves as
%% the entry point for the cb_accounts application in the Kinetic Core banking system.
%%
%% h2. Application Role
%%
%% The cb_accounts application is responsible for managing the lifecycle of
%% bank accounts. It provides:
%% <ul>
%%   <li>Account creation and initialization</li>
%%   <li>Account status management (active, frozen, closed)</li>
%%   <li>Account queries and listings</li>
%%   <li>Balance retrieval</li>
%% </ul>
%%
%% h2. Dependencies
%%
%% This application depends on:
%% <ul>
%%   <li>{@link cb_party} - For party (customer) validation when creating accounts</li>
%%   <li>{@link cb_ledger} - For the account record definition and balance tracking</li>
%% </ul>
%%
%% h2. Supervision Structure
%%
%% This application starts a top-level supervisor ({@link cb_accounts_sup})
%% which manages all child processes. The supervisor uses a one_for_one
%% restart strategy, meaning if any child process crashes, only that
%% specific process is restarted.
%%
%% h2. Configuration
%%
%% This application does not currently require runtime configuration.
%% All settings are defined in the application resource file (cb_accounts.app).
%%
%% @see application
%% @see cb_accounts_sup
%% @see cb_accounts

-module(cb_accounts_app).
-behaviour(application).

-export([start/2, stop/1, config_change/3]).

%% =============================================================================
%% Application Behaviour Callbacks
%% =============================================================================

%% @doc Starts the cb_accounts application.
%%
%% Called by the OTP application controller when starting this application.
%% This function starts the top-level supervisor which in turn manages
%% all child processes for this application.
%%
%% h4. Start Type
%% The `_StartType` parameter indicates how the application is being started:
%% <ul>
%%   <li><strong>normal</strong> - Normal startup (most common)</li>
%%   <li><strong>{takeover, Node}</strong> - Application takeover from another node</li>
%%   <li><strong>{failover, Node}</strong> - Application failover to this node</li>
%% </ul>
%%
%% @param StartType The type of startup (normally 'normal')
%% @param StartArgs Arguments passed to the application (ignored)
%% @returns {@type {ok, pid()}} on success, {@type {error, any()}} on failure
%%
-spec start(normal, any()) -> {ok, pid()} | {error, any()}.
start(_StartType, _StartArgs) ->
    cb_accounts_sup:start_link().

%% @doc Stops the cb_accounts application.
%%
%% Called by the OTP application controller when stopping this application.
%% Performs any necessary cleanup. Since cb_accounts is a readmostly
%% application with no persistent state beyond Mnesia, no explicit
%% cleanup is required.
%%
%% @param State The application state (ignored - cb_accounts is stateless)
%% @returns {@type ok} - This function always returns ok
%%
-spec stop(any()) -> ok.
stop(_State) ->
    ok.

%% @doc Handles configuration changes at runtime.
%%
%% Called when the application configuration is changed using
%% `application:set_env/3` or similar. This allows the application
%% to adapt to configuration changes without restart.
%%
%% h4. Change Types
%% <ul>
%%   <li><strong>Changed</strong> - List of configuration keys that were modified</li>
%%   <li><strong>New</strong> - List of new configuration keys</li>
%%   <li><strong>Removed</strong> - List of configuration keys that were removed</li>
%% </ul>
%%
%% @param Changed List of changed configuration parameter names
%% @param New List of new configuration parameter names
%% @param Removed List of removed configuration parameter names
%% @returns {@type ok} - This function always returns ok
%%
-spec config_change(list(), list(), list()) -> ok.
config_change(_Changed, _New, _Removed) ->
    ok.
