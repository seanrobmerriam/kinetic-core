%% @doc CT tests for cb_connectors — TASK-054 lifecycle and registry.
-module(cb_connectors_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    register_connector_ok/1,
    get_connector_not_found/1,
    list_connectors_empty/1,
    list_connectors_returns_all/1,
    enable_connector_ok/1,
    disable_connector_ok/1,
    deprecate_connector_ok/1,
    cannot_enable_deprecated/1,
    cannot_disable_already_disabled/1,
    update_connector_fields/1,
    list_by_type/1,
    list_by_status/1
]).

all() ->
    [
        register_connector_ok,
        get_connector_not_found,
        list_connectors_empty,
        list_connectors_returns_all,
        enable_connector_ok,
        disable_connector_ok,
        deprecate_connector_ok,
        cannot_enable_deprecated,
        cannot_disable_already_disabled,
        update_connector_fields,
        list_by_type,
        list_by_status
    ].

init_per_suite(Config) ->
    mnesia:start(),
    cb_schema:create_tables(),
    Config.

end_per_suite(_Config) ->
    mnesia:stop(),
    mnesia:delete_schema([node()]),
    ok.

init_per_testcase(_TestCase, Config) ->
    mnesia:clear_table(connector_definition),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

make_attrs(Name) ->
    #{
        name          => Name,
        type          => aws,
        module        => cb_connector_aws,
        version       => <<"1.0.0">>,
        capabilities  => [<<"s3">>, <<"lambda">>],
        config_schema => #{region => <<"us-east-1">>},
        description   => <<"Test connector">>
    }.

register_connector_ok(_Config) ->
    {ok, C} = cb_connectors:register(make_attrs(<<"AWS Test">>)),
    ?assertEqual(<<"AWS Test">>, C#connector_definition.name),
    ?assertEqual(registered, C#connector_definition.status),
    ?assertEqual(aws, C#connector_definition.type).

get_connector_not_found(_Config) ->
    ?assertEqual({error, not_found}, cb_connectors:get(<<"nonexistent">>)).

list_connectors_empty(_Config) ->
    ?assertEqual([], cb_connectors:list()).

list_connectors_returns_all(_Config) ->
    {ok, _} = cb_connectors:register(make_attrs(<<"C1">>)),
    {ok, _} = cb_connectors:register(make_attrs(<<"C2">>)),
    All = cb_connectors:list(),
    ?assertEqual(2, length(All)).

enable_connector_ok(_Config) ->
    {ok, C} = cb_connectors:register(make_attrs(<<"Enable Test">>)),
    {ok, Enabled} = cb_connectors:enable(C#connector_definition.connector_id),
    ?assertEqual(enabled, Enabled#connector_definition.status).

disable_connector_ok(_Config) ->
    {ok, C}       = cb_connectors:register(make_attrs(<<"Disable Test">>)),
    {ok, Enabled} = cb_connectors:enable(C#connector_definition.connector_id),
    {ok, Disabled} = cb_connectors:disable(Enabled#connector_definition.connector_id),
    ?assertEqual(disabled, Disabled#connector_definition.status).

deprecate_connector_ok(_Config) ->
    {ok, C}       = cb_connectors:register(make_attrs(<<"Deprecate Test">>)),
    {ok, Enabled} = cb_connectors:enable(C#connector_definition.connector_id),
    {ok, Depr}    = cb_connectors:deprecate(Enabled#connector_definition.connector_id),
    ?assertEqual(deprecated, Depr#connector_definition.status).

cannot_enable_deprecated(_Config) ->
    {ok, C}    = cb_connectors:register(make_attrs(<<"Deprecated">>)),
    {ok, En}   = cb_connectors:enable(C#connector_definition.connector_id),
    {ok, Depr} = cb_connectors:deprecate(En#connector_definition.connector_id),
    ?assertMatch({error, {invalid_transition, deprecated, enabled}},
                 cb_connectors:enable(Depr#connector_definition.connector_id)).

cannot_disable_already_disabled(_Config) ->
    {ok, C}       = cb_connectors:register(make_attrs(<<"Already Disabled">>)),
    {ok, Enabled} = cb_connectors:enable(C#connector_definition.connector_id),
    {ok, _Dis}    = cb_connectors:disable(Enabled#connector_definition.connector_id),
    ?assertMatch({error, {invalid_transition, disabled, disabled}},
                 cb_connectors:disable(Enabled#connector_definition.connector_id)).

update_connector_fields(_Config) ->
    {ok, C} = cb_connectors:register(make_attrs(<<"Update Test">>)),
    {ok, U} = cb_connectors:update(C#connector_definition.connector_id,
                                   #{description => <<"Updated desc">>}),
    ?assertEqual(<<"Updated desc">>, U#connector_definition.description).

list_by_type(_Config) ->
    {ok, _} = cb_connectors:register(make_attrs(<<"AWS One">>)),
    {ok, _} = cb_connectors:register(#{
        name => <<"Azure One">>, type => azure, module => cb_connector_azure,
        version => <<"1.0.0">>, capabilities => [<<"blob">>],
        config_schema => #{}, description => <<>>
    }),
    AWSList = cb_connectors:list_by_type(aws),
    ?assertEqual(1, length(AWSList)),
    ?assertEqual(aws, (hd(AWSList))#connector_definition.type).

list_by_status(_Config) ->
    {ok, C1} = cb_connectors:register(make_attrs(<<"S1">>)),
    {ok, _C2} = cb_connectors:register(make_attrs(<<"S2">>)),
    {ok, _}   = cb_connectors:enable(C1#connector_definition.connector_id),
    Enabled = cb_connectors:list_by_status(enabled),
    ?assertEqual(1, length(Enabled)).
