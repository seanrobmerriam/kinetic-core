%% @doc CT tests for cb_partner_onboarding — TASK-056 partner workflow.
-module(cb_partner_onboarding_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    submit_application_ok/1,
    get_application_not_found/1,
    list_pending_after_submit/1,
    approve_application_ok/1,
    reject_application_ok/1,
    cannot_approve_already_approved/1,
    compatibility_ok_when_connectors_enabled/1,
    compatibility_fails_when_connectors_not_enabled/1
]).

all() ->
    [
        submit_application_ok,
        get_application_not_found,
        list_pending_after_submit,
        approve_application_ok,
        reject_application_ok,
        cannot_approve_already_approved,
        compatibility_ok_when_connectors_enabled,
        compatibility_fails_when_connectors_not_enabled
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
    mnesia:clear_table(partner_application),
    mnesia:clear_table(connector_definition),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

make_app_attrs() ->
    #{
        name                 => <<"Acme Corp">>,
        contact_email        => <<"ops@acme.com">>,
        requested_connectors => []
    }.

submit_application_ok(_Config) ->
    {ok, App} = cb_partner_onboarding:submit_application(make_app_attrs()),
    ?assertEqual(<<"Acme Corp">>, App#partner_application.name),
    ?assertEqual(pending, App#partner_application.status).

get_application_not_found(_Config) ->
    ?assertEqual({error, not_found}, cb_partner_onboarding:get_application(<<"nonexistent">>)).

list_pending_after_submit(_Config) ->
    {ok, _} = cb_partner_onboarding:submit_application(make_app_attrs()),
    {ok, _} = cb_partner_onboarding:submit_application(make_app_attrs()),
    Pending = cb_partner_onboarding:list_pending(),
    ?assertEqual(2, length(Pending)).

approve_application_ok(_Config) ->
    {ok, App} = cb_partner_onboarding:submit_application(make_app_attrs()),
    {ok, Approved} = cb_partner_onboarding:approve(App#partner_application.application_id, <<"admin-1">>),
    ?assertEqual(approved, Approved#partner_application.status),
    ?assertEqual(<<"admin-1">>, Approved#partner_application.reviewed_by).

reject_application_ok(_Config) ->
    {ok, App} = cb_partner_onboarding:submit_application(make_app_attrs()),
    {ok, Rejected} = cb_partner_onboarding:reject(App#partner_application.application_id,
                                                   <<"admin-1">>, <<"Does not meet criteria">>),
    ?assertEqual(rejected, Rejected#partner_application.status),
    ?assertEqual(<<"Does not meet criteria">>, Rejected#partner_application.rejection_reason).

cannot_approve_already_approved(_Config) ->
    {ok, App}  = cb_partner_onboarding:submit_application(make_app_attrs()),
    AppId      = App#partner_application.application_id,
    {ok, _}    = cb_partner_onboarding:approve(AppId, <<"admin">>),
    ?assertMatch({error, {invalid_transition, approved, approved}},
                 cb_partner_onboarding:approve(AppId, <<"admin">>)).

compatibility_ok_when_connectors_enabled(_Config) ->
    Attrs = #{
        name => <<"AWS Conn">>, type => aws, module => cb_connector_aws,
        version => <<"1.0.0">>, capabilities => [], config_schema => #{}, description => <<>>
    },
    {ok, C}  = cb_connectors:register(Attrs),
    ConnId   = C#connector_definition.connector_id,
    {ok, _}  = cb_connectors:enable(ConnId),
    ?assertEqual(ok, cb_partner_onboarding:check_compatibility([ConnId])).

compatibility_fails_when_connectors_not_enabled(_Config) ->
    Attrs = #{
        name => <<"Disabled Conn">>, type => aws, module => cb_connector_aws,
        version => <<"1.0.0">>, capabilities => [], config_schema => #{}, description => <<>>
    },
    {ok, C} = cb_connectors:register(Attrs),
    ConnId  = C#connector_definition.connector_id,
    ?assertMatch({error, {incompatible_connectors, [ConnId]}},
                 cb_partner_onboarding:check_compatibility([ConnId])).
