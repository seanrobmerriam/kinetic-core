%% @doc AWS connector baseline pack.
%%
%% Implements cb_connector_behaviour for core AWS services:
%% S3, Lambda, SQS, DynamoDB.
%%
%% This is a stub/baseline pack — actual HTTP dispatch to AWS is not
%% performed. The module provides the connector contract so partner
%% integrations can be registered and health-checked against a real
%% implementation that would be layered on top.
-module(cb_connector_aws).
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
name() -> <<"AWS Connector Pack">>.

-spec version() -> binary().
version() -> <<"1.0.0">>.

-spec capabilities() -> [binary()].
capabilities() -> [<<"s3">>, <<"lambda">>, <<"sqs">>, <<"dynamodb">>].

-spec init(map()) -> {ok, map()} | {error, term()}.
init(Config) ->
    RequiredKeys = [region],
    Missing = [K || K <- RequiredKeys, not maps:is_key(K, Config)],
    case Missing of
        [] ->
            State = #{
                region  => maps:get(region, Config),
                profile => maps:get(profile, Config, <<"default">>)
            },
            {ok, State};
        _ ->
            {error, {missing_config_keys, Missing}}
    end.

-spec execute(binary(), map()) -> {ok, map()} | {error, term()}.
execute(<<"s3:put_object">>, #{bucket := Bucket, key := Key}) ->
    {ok, #{service => s3, action => put_object, bucket => Bucket, key => Key, status => simulated}};
execute(<<"s3:get_object">>, #{bucket := Bucket, key := Key}) ->
    {ok, #{service => s3, action => get_object, bucket => Bucket, key => Key, status => simulated}};
execute(<<"lambda:invoke">>, #{function_name := FnName}) ->
    {ok, #{service => lambda, action => invoke, function_name => FnName, status => simulated}};
execute(<<"sqs:send_message">>, #{queue_url := QueueUrl, body := Body}) ->
    {ok, #{service => sqs, action => send_message, queue_url => QueueUrl, body => Body, status => simulated}};
execute(<<"dynamodb:put_item">>, #{table := Table, item := Item}) ->
    {ok, #{service => dynamodb, action => put_item, table => Table, item => Item, status => simulated}};
execute(Action, _Params) ->
    {error, {unsupported_action, Action}}.

-spec health_check() -> ok | {error, term()}.
health_check() ->
    ok.

-spec terminate(term()) -> ok.
terminate(_Reason) ->
    ok.
