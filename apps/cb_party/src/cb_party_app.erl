%% @doc
%% <h2>Party Application Module</h2>
%%
%% This module implements the OTP application behaviour for the cb_party application.
%% It serves as the entry point for starting the party management subsystem in the
%% Kinetic Core core banking system.
%%
%% <h3>Role in the System</h3>
%%
%% In OTP (Open Telecom Platform), an application is the basic unit of deployment.
%% The cb_party application manages:
%% <ul>
%%   <li>Party lifecycle operations (create, suspend, reactivate, close)</li>
%%   <li>Customer data persistence in Mnesia</li>
%%   <li>Business rule enforcement for party state transitions</li>
%% </ul>
%%
%% <h3>Startup Sequence</h3>
%%
%% <ol>
%%   <li>The Erlang node starts and loads the application</li>
%%   <li>application:start/2 calls cb_party_app:start/2</li>
%%   <li>start/2 calls cb_party_sup:start_link/0</li>
%%   <li>The supervisor tree initializes</li>
%% </ol>
%%
%% <h3>Supervision Structure</h3>
%%
%% The cb_party application uses a simple one_for_one supervisor strategy:
%% <ul>
%%   <li><b>cb_party_sup</b>: Top-level supervisor that manages worker processes</li>
%%   <li>Currently starts with no children (extension point for future workers)</li>
%% </ul>
%%
%% @see cb_party_sup for the supervisor implementation
-module(cb_party_app).
-behaviour(application).

-export([start/2, stop/1]).

-spec start(normal, any()) -> {ok, pid()} | {error, any()}.
start(_StartType, _StartArgs) ->
    cb_party_sup:start_link().

-spec stop(any()) -> ok.
stop(_State) ->
    ok.
