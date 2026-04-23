%% @doc Connector behaviour — contract all marketplace connectors must implement.
%%
%% Any module registered as a connector must export these callbacks.
%% The lifecycle is managed by cb_connectors; these callbacks handle
%% runtime execution and introspection.
-module(cb_connector_behaviour).

-callback name() -> binary().
%% Returns the human-readable connector name.

-callback version() -> binary().
%% Returns the connector's semantic version string (e.g., <<"1.0.0">>).

-callback capabilities() -> [binary()].
%% Returns the list of capability identifiers this connector provides.

-callback init(Config :: map()) -> {ok, state()} | {error, term()}.
%% Called once when the connector is loaded. Config is the stored config_schema map.

-callback execute(Action :: binary(), Params :: map()) -> {ok, map()} | {error, term()}.
%% Called to perform a connector action. Action identifies the operation;
%% Params supplies input. Returns structured result or error.

-callback health_check() -> ok | {error, term()}.
%% Probes connector health. Returns ok when the connector is reachable/ready.

-callback terminate(Reason :: term()) -> ok.
%% Called on graceful shutdown. Connector should release any held resources.

-type state() :: map().
-export_type([state/0]).
