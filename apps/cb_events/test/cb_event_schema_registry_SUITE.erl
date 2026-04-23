-module(cb_event_schema_registry_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([
    register_schema_ok/1,
    get_schema_ok/1,
    get_schema_not_found/1,
    list_versions_ok/1,
    latest_version_ok/1,
    compatibility_backward_ok/1,
    compatibility_forward_ok/1,
    compatibility_full_ok/1,
    compatibility_none_ok/1
]).

all() ->
    [
        register_schema_ok,
        get_schema_ok,
        get_schema_not_found,
        list_versions_ok,
        latest_version_ok,
        compatibility_backward_ok,
        compatibility_forward_ok,
        compatibility_full_ok,
        compatibility_none_ok
    ].

init_per_suite(Config) ->
    mnesia:start(),
    cb_schema:create_tables(),
    Config.

end_per_suite(_Config) ->
    mnesia:stop(),
    ok.

register_schema_ok(_Config) ->
    Params = #{event_type    => <<"payment.created">>,
               version       => 1,
               schema        => #{fields => [<<"amount">>, <<"currency">>]},
               compatibility => backward},
    {ok, SchemaId} = cb_event_schema_registry:register(Params),
    ?assert(is_binary(SchemaId)).

get_schema_ok(_Config) ->
    Params = #{event_type    => <<"test.event">>,
               version       => 1,
               schema        => #{fields => [<<"id">>]},
               compatibility => none},
    {ok, _} = cb_event_schema_registry:register(Params),
    {ok, Schema} = cb_event_schema_registry:get_schema(<<"test.event">>, 1),
    ?assertEqual(<<"test.event">>, Schema#event_schema_version.event_type),
    ?assertEqual(1, Schema#event_schema_version.version).

get_schema_not_found(_Config) ->
    {error, not_found} = cb_event_schema_registry:get_schema(<<"no.such.event">>, 999).

list_versions_ok(_Config) ->
    EventType = <<"multi.version">>,
    cb_event_schema_registry:register(#{event_type => EventType, version => 1,
                                        schema => #{fields => []}, compatibility => backward}),
    cb_event_schema_registry:register(#{event_type => EventType, version => 2,
                                        schema => #{fields => [<<"x">>]}, compatibility => backward}),
    Versions = cb_event_schema_registry:list_versions(EventType),
    ?assert(length(Versions) >= 2).

latest_version_ok(_Config) ->
    EventType = <<"latest.test">>,
    cb_event_schema_registry:register(#{event_type => EventType, version => 1,
                                        schema => #{fields => []}, compatibility => none}),
    cb_event_schema_registry:register(#{event_type => EventType, version => 3,
                                        schema => #{fields => []}, compatibility => none}),
    cb_event_schema_registry:register(#{event_type => EventType, version => 2,
                                        schema => #{fields => []}, compatibility => none}),
    {ok, Schema} = cb_event_schema_registry:latest_version(EventType),
    ?assertEqual(3, Schema#event_schema_version.version).

compatibility_backward_ok(_Config) ->
    OldFields = [<<"amount">>, <<"currency">>],
    NewFields = [<<"amount">>, <<"currency">>, <<"description">>],
    Old = #{fields => OldFields},
    New = #{fields => NewFields},
    ?assertEqual(ok,
                 cb_event_schema_registry:check_compatibility(Old, New, backward)).

compatibility_forward_ok(_Config) ->
    OldFields = [<<"amount">>, <<"currency">>, <<"extra">>],
    NewFields = [<<"amount">>, <<"currency">>],
    Old = #{fields => OldFields},
    New = #{fields => NewFields},
    ?assertEqual(ok,
                 cb_event_schema_registry:check_compatibility(Old, New, forward)).

compatibility_full_ok(_Config) ->
    Fields = [<<"amount">>, <<"currency">>],
    Schema = #{fields => Fields},
    ?assertEqual(ok,
                 cb_event_schema_registry:check_compatibility(Schema, Schema, full)).

compatibility_none_ok(_Config) ->
    ?assertEqual(ok,
                 cb_event_schema_registry:check_compatibility(#{fields => []}, #{fields => []}, none)).
