-module(cb_aml_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    %% Rules
    create_rule_ok/1,
    get_rule_ok/1,
    list_rules_ok/1,
    update_rule_ok/1,
    delete_rule_ok/1,
    %% Suspicious activity
    create_alert_ok/1,
    get_alert_ok/1,
    list_alerts_ok/1,
    list_alerts_by_status_ok/1,
    review_alert_ok/1,
    %% Cases
    create_case_ok/1,
    get_case_ok/1,
    list_cases_ok/1,
    update_case_ok/1,
    %% Error path
    get_rule_not_found/1,
    get_alert_not_found/1,
    get_case_not_found/1,
    review_alert_invalid_status/1
]).

all() ->
    [
        create_rule_ok,
        get_rule_ok,
        list_rules_ok,
        update_rule_ok,
        delete_rule_ok,
        create_alert_ok,
        get_alert_ok,
        list_alerts_ok,
        list_alerts_by_status_ok,
        review_alert_ok,
        create_case_ok,
        get_case_ok,
        list_cases_ok,
        update_case_ok,
        get_rule_not_found,
        get_alert_not_found,
        get_case_not_found,
        review_alert_invalid_status
    ].

init_per_suite(Config) ->
    mnesia:start(),
    Tables = [
        {aml_rule, [
            {ram_copies, [node()]},
            {attributes, record_info(fields, aml_rule)},
            {index, [enabled, condition_type]}
        ]},
        {suspicious_activity, [
            {ram_copies, [node()]},
            {attributes, record_info(fields, suspicious_activity)},
            {index, [party_id, status, rule_id]}
        ]},
        {aml_case, [
            {ram_copies, [node()]},
            {attributes, record_info(fields, aml_case)},
            {index, [party_id, status]}
        ]},
        {party, [
            {ram_copies, [node()]},
            {attributes, record_info(fields, party)},
            {index, [status, kyc_status, risk_tier]}
        ]}
    ],
    lists:foreach(fun({Table, Opts}) ->
        case mnesia:create_table(Table, Opts) of
            {atomic, ok} -> ok;
            {aborted, {already_exists, _}} -> ok;
            {aborted, Reason} -> error({failed_to_create_table, Table, Reason})
        end
    end, Tables),
    Config.

end_per_suite(_Config) ->
    mnesia:stop(),
    mnesia:delete_schema([node()]),
    ok.

init_per_testcase(_TestCase, Config) ->
    mnesia:clear_table(aml_rule),
    mnesia:clear_table(suspicious_activity),
    mnesia:clear_table(aml_case),
    mnesia:clear_table(party),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

%% =============================================================================
%% Rule Tests
%% =============================================================================

create_rule_ok(_Config) ->
    {ok, Rule} = cb_aml:create_rule(#{
        name => <<"High Value Transfer">>,
        description => <<"Flag transfers over 10000">>,
        condition_type => amount_threshold,
        threshold_value => 10000,
        action => flag,
        enabled => true
    }),
    ?assertEqual(<<"High Value Transfer">>, Rule#aml_rule.name),
    ?assertEqual(amount_threshold, Rule#aml_rule.condition_type),
    ?assertEqual(10000, Rule#aml_rule.threshold_value),
    ?assertEqual(flag, Rule#aml_rule.action),
    ?assertEqual(true, Rule#aml_rule.enabled),
    ?assert(is_binary(Rule#aml_rule.rule_id)),
    ok.

get_rule_ok(_Config) ->
    {ok, R} = cb_aml:create_rule(#{
        name => <<"Test Rule">>, description => <<"d">>,
        condition_type => velocity, threshold_value => 5,
        action => alert, enabled => true
    }),
    {ok, Got} = cb_aml:get_rule(R#aml_rule.rule_id),
    ?assertEqual(R#aml_rule.rule_id, Got#aml_rule.rule_id),
    ok.

list_rules_ok(_Config) ->
    {ok, _R1} = cb_aml:create_rule(#{
        name => <<"R1">>, description => <<"d1">>,
        condition_type => amount_threshold, threshold_value => 1000,
        action => flag, enabled => true
    }),
    {ok, _R2} = cb_aml:create_rule(#{
        name => <<"R2">>, description => <<"d2">>,
        condition_type => velocity, threshold_value => 10,
        action => block, enabled => false
    }),
    {ok, Rules} = cb_aml:list_rules(),
    ?assertEqual(2, length(Rules)),
    ok.

update_rule_ok(_Config) ->
    {ok, R} = cb_aml:create_rule(#{
        name => <<"Rule">>, description => <<"original desc">>,
        condition_type => velocity, threshold_value => 5,
        action => alert, enabled => true
    }),
    {ok, Updated} = cb_aml:update_rule(R#aml_rule.rule_id, #{
        description => <<"updated desc">>,
        enabled => false
    }),
    ?assertEqual(<<"updated desc">>, Updated#aml_rule.description),
    ?assertEqual(false, Updated#aml_rule.enabled),
    ?assertEqual(2, Updated#aml_rule.version),
    ok.

delete_rule_ok(_Config) ->
    {ok, R} = cb_aml:create_rule(#{
        name => <<"To Delete">>, description => <<"d">>,
        condition_type => amount_threshold, threshold_value => 500,
        action => alert, enabled => true
    }),
    ok = cb_aml:delete_rule(R#aml_rule.rule_id),
    {error, not_found} = cb_aml:get_rule(R#aml_rule.rule_id),
    ok.

%% =============================================================================
%% Suspicious Activity Tests
%% =============================================================================

create_alert_ok(_Config) ->
    {ok, R} = cb_aml:create_rule(#{
        name => <<"R">>, description => <<"d">>,
        condition_type => amount_threshold, threshold_value => 1000,
        action => flag, enabled => true
    }),
    {ok, Alert} = cb_aml:create_alert(#{
        party_id => <<"party-001">>,
        txn_id => <<"txn-001">>,
        rule_id => R#aml_rule.rule_id,
        reason => <<"Large transfer">>,
        risk_score => 75,
        metadata => #{}
    }),
    ?assertEqual(<<"party-001">>, Alert#suspicious_activity.party_id),
    ?assertEqual(open, Alert#suspicious_activity.status),
    ?assertEqual(75, Alert#suspicious_activity.risk_score),
    ok.

get_alert_ok(_Config) ->
    {ok, R} = cb_aml:create_rule(#{
        name => <<"R">>, description => <<"d">>,
        condition_type => velocity, threshold_value => 10,
        action => alert, enabled => true
    }),
    {ok, A} = cb_aml:create_alert(#{
        party_id => <<"p1">>, txn_id => <<"t1">>,
        rule_id => R#aml_rule.rule_id,
        reason => <<"Velocity">>, risk_score => 50, metadata => #{}
    }),
    {ok, Got} = cb_aml:get_alert(A#suspicious_activity.alert_id),
    ?assertEqual(A#suspicious_activity.alert_id, Got#suspicious_activity.alert_id),
    ok.

list_alerts_ok(_Config) ->
    {ok, R} = cb_aml:create_rule(#{
        name => <<"R">>, description => <<"d">>,
        condition_type => amount_threshold, threshold_value => 100,
        action => flag, enabled => true
    }),
    RuleId = R#aml_rule.rule_id,
    {ok, _A1} = cb_aml:create_alert(#{
        party_id => <<"p1">>, txn_id => <<"t1">>, rule_id => RuleId,
        reason => <<"r1">>, risk_score => 10, metadata => #{}
    }),
    {ok, _A2} = cb_aml:create_alert(#{
        party_id => <<"p2">>, txn_id => <<"t2">>, rule_id => RuleId,
        reason => <<"r2">>, risk_score => 20, metadata => #{}
    }),
    {ok, Alerts} = cb_aml:list_alerts(),
    ?assertEqual(2, length(Alerts)),
    ok.

list_alerts_by_status_ok(_Config) ->
    {ok, R} = cb_aml:create_rule(#{
        name => <<"R">>, description => <<"d">>,
        condition_type => amount_threshold, threshold_value => 100,
        action => flag, enabled => true
    }),
    RuleId = R#aml_rule.rule_id,
    {ok, A} = cb_aml:create_alert(#{
        party_id => <<"p1">>, txn_id => <<"t1">>, rule_id => RuleId,
        reason => <<"r1">>, risk_score => 10, metadata => #{}
    }),
    {ok, _} = cb_aml:review_alert(A#suspicious_activity.alert_id, cleared, <<"reviewer-1">>),
    {ok, _} = cb_aml:create_alert(#{
        party_id => <<"p2">>, txn_id => <<"t2">>, rule_id => RuleId,
        reason => <<"r2">>, risk_score => 20, metadata => #{}
    }),
    {ok, OpenAlerts} = cb_aml:list_alerts_by_status(open),
    ?assertEqual(1, length(OpenAlerts)),
    ok.

review_alert_ok(_Config) ->
    {ok, R} = cb_aml:create_rule(#{
        name => <<"R">>, description => <<"d">>,
        condition_type => velocity, threshold_value => 5,
        action => alert, enabled => true
    }),
    {ok, A} = cb_aml:create_alert(#{
        party_id => <<"p1">>, txn_id => <<"t1">>,
        rule_id => R#aml_rule.rule_id,
        reason => <<"r">>, risk_score => 30, metadata => #{}
    }),
    {ok, Reviewed} = cb_aml:review_alert(A#suspicious_activity.alert_id, escalated, <<"reviewer-1">>),
    ?assertEqual(escalated, Reviewed#suspicious_activity.status),
    ok.

%% =============================================================================
%% Case Tests
%% =============================================================================

create_case_ok(_Config) ->
    {ok, R} = cb_aml:create_rule(#{
        name => <<"R">>, description => <<"d">>,
        condition_type => amount_threshold, threshold_value => 100,
        action => flag, enabled => true
    }),
    {ok, A} = cb_aml:create_alert(#{
        party_id => <<"party-001">>, txn_id => <<"t1">>,
        rule_id => R#aml_rule.rule_id,
        reason => <<"r">>, risk_score => 80, metadata => #{}
    }),
    {ok, Case} = cb_aml:create_case(#{
        party_id => <<"party-001">>,
        alert_ids => [A#suspicious_activity.alert_id],
        summary => <<"Suspicious high-value transfers">>
    }),
    ?assertEqual(<<"party-001">>, Case#aml_case.party_id),
    ?assertEqual(open, Case#aml_case.status),
    ?assert(is_binary(Case#aml_case.case_id)),
    ok.

get_case_ok(_Config) ->
    {ok, C} = cb_aml:create_case(#{
        party_id => <<"p1">>, alert_ids => [],
        summary => <<"Test case">>
    }),
    {ok, Got} = cb_aml:get_case(C#aml_case.case_id),
    ?assertEqual(C#aml_case.case_id, Got#aml_case.case_id),
    ok.

list_cases_ok(_Config) ->
    {ok, _C1} = cb_aml:create_case(#{party_id => <<"p1">>, alert_ids => [], summary => <<"s1">>}),
    {ok, _C2} = cb_aml:create_case(#{party_id => <<"p2">>, alert_ids => [], summary => <<"s2">>}),
    {ok, Cases} = cb_aml:list_cases(),
    ?assertEqual(2, length(Cases)),
    ok.

update_case_ok(_Config) ->
    {ok, C} = cb_aml:create_case(#{
        party_id => <<"p1">>, alert_ids => [],
        summary => <<"Original summary">>
    }),
    {ok, Updated} = cb_aml:update_case(C#aml_case.case_id, #{
        status => investigating,
        assignee => <<"analyst-001">>
    }),
    ?assertEqual(investigating, Updated#aml_case.status),
    ?assertEqual(<<"analyst-001">>, Updated#aml_case.assignee),
    ok.

%% =============================================================================
%% Error Path Tests
%% =============================================================================

get_rule_not_found(_Config) ->
    {error, not_found} = cb_aml:get_rule(<<"no-such-rule">>),
    ok.

get_alert_not_found(_Config) ->
    {error, not_found} = cb_aml:get_alert(<<"no-such-alert">>),
    ok.

get_case_not_found(_Config) ->
    {error, not_found} = cb_aml:get_case(<<"no-such-case">>),
    ok.

review_alert_invalid_status(_Config) ->
    {ok, R} = cb_aml:create_rule(#{
        name => <<"R">>, description => <<"d">>,
        condition_type => amount_threshold, threshold_value => 100,
        action => flag, enabled => true
    }),
    {ok, A} = cb_aml:create_alert(#{
        party_id => <<"p1">>, txn_id => <<"t1">>,
        rule_id => R#aml_rule.rule_id,
        reason => <<"r">>, risk_score => 10, metadata => #{}
    }),
    {ok, _} = cb_aml:review_alert(A#suspicious_activity.alert_id, cleared, <<"r1">>),
    %% Alert is now cleared — a second review attempt must fail
    {error, invalid_alert_status} = cb_aml:review_alert(A#suspicious_activity.alert_id, cleared, <<"r2">>),
    ok.
