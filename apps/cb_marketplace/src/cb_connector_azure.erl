%% @doc Azure connector baseline pack.
%%
%% Implements cb_connector_behaviour for core Azure services:
%% Blob Storage, Functions, Event Hubs.
%%
%% This is a stub/baseline pack — actual HTTP dispatch to Azure is not
%% performed. The module provides the connector contract so partner
%% integrations can be registered and health-checked against a real
%% implementation that would be layered on top.
-module(cb_connector_azure).
-behaviour(cb_connector_behaviour).

-export([
    name/0,
    version/0,
    capabilities/0,
    init/1,
    execute/2,
    health_check/0,
    terminate/1
]).

-spec name() -> binary().
name() -> <<"Azure Connector Pack">>.

-spec version() -> binary().
version() -> <<"1.0.0">>.

-spec capabilities() -> [binary()].
capabilities() -> [<<"blob">>, <<"functions">>, <<"event_hubs">>].

-spec init(map()) -> {ok, map()} | {error, term()}.
init(Config) ->
    RequiredKeys = [tenant_id, subscription_id],
    Missing = [K || K <- RequiredKeys, not maps:is_key(K, Config)],
    case Missing of
        [] ->
            State = #{
                tenant_id       => maps:get(tenant_id, Config),
                subscription_id => maps:get(subscription_id, Config),
                resource_group  => maps:get(resource_group, Config, <<"default">>)
            },
            {ok, State};
        _ ->
            {error, {missing_config_keys, Missing}}
    end.

-spec execute(binary(), map()) -> {ok, map()} | {error, term()}.
execute(<<"blob:upload">>, #{container := Container, name := Name}) ->
    {ok, #{service => blob, action => upload, container => Container, name => Name, status => simulated}};
execute(<<"blob:download">>, #{container := Container, name := Name}) ->
    {ok, #{service => blob, action => download, container => Container, name => Name, status => simulated}};
execute(<<"functions:invoke">>, #{function_name := FnName}) ->
    {ok, #{service => functions, action => invoke, function_name => FnName, status => simulated}};
execute(<<"event_hubs:send">>, #{hub := Hub, event := Event}) ->
    {ok, #{service => event_hubs, action => send, hub => Hub, event => Event, status => simulated}};
execute(Action, _Params) ->
    {error, {unsupported_action, Action}}.

-spec health_check() -> ok | {error, term()}.
health_check() ->
    ok.

-spec terminate(term()) -> ok.
terminate(_Reason) ->
    ok.
