-module(cb_posting_templates_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    list_templates_returns_all/1,
    get_template_fee/1,
    get_template_interest/1,
    get_template_interest_credit/1,
    get_template_operational_adjustment/1,
    get_template_reversal_adjustment/1,
    get_template_not_found/1,
    apply_template_fee/1,
    apply_template_interest/1,
    apply_template_missing_fields/1,
    apply_template_not_found/1
]).

all() ->
    [
        list_templates_returns_all,
        get_template_fee,
        get_template_interest,
        get_template_interest_credit,
        get_template_operational_adjustment,
        get_template_reversal_adjustment,
        get_template_not_found,
        apply_template_fee,
        apply_template_interest,
        apply_template_missing_fields,
        apply_template_not_found
    ].

init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    ok.

init_per_testcase(_TestCase, Config) ->
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

%% ─── list_templates ──────────────────────────────────────────────────────────

list_templates_returns_all(_Config) ->
    Templates = cb_posting_templates:list_templates(),
    ?assert(length(Templates) >= 5),
    Names = [maps:get(name, T) || T <- Templates],
    ?assert(lists:member(fee, Names)),
    ?assert(lists:member(interest, Names)),
    ?assert(lists:member(interest_credit, Names)),
    ?assert(lists:member(operational_adjustment, Names)),
    ?assert(lists:member(reversal_adjustment, Names)),
    ok.

%% ─── get_template ────────────────────────────────────────────────────────────

get_template_fee(_Config) ->
    {ok, _T} = cb_posting_templates:get_template(fee),
    ok.

get_template_interest(_Config) ->
    {ok, _T} = cb_posting_templates:get_template(interest),
    ok.

get_template_interest_credit(_Config) ->
    {ok, _T} = cb_posting_templates:get_template(interest_credit),
    ok.

get_template_operational_adjustment(_Config) ->
    {ok, _T} = cb_posting_templates:get_template(operational_adjustment),
    ok.

get_template_reversal_adjustment(_Config) ->
    {ok, _T} = cb_posting_templates:get_template(reversal_adjustment),
    ok.

get_template_not_found(_Config) ->
    {error, Reason} = cb_posting_templates:get_template(does_not_exist),
    ?assertEqual(template_not_found, Reason),
    ok.

%% ─── apply_template ──────────────────────────────────────────────────────────

apply_template_fee(_Config) ->
    AccountId = <<"account-001">>,
    Params = #{amount => 500, currency => 'USD', note => <<"monthly fee">>},
    {ok, {Aid, Amount, Currency, Description}} = cb_posting_templates:apply_template(fee, AccountId, Params),
    ?assertEqual(AccountId, Aid),
    ?assertEqual(500, Amount),
    ?assertEqual('USD', Currency),
    ?assert(binary:match(Description, <<"Fee charge:">>) =/= nomatch),
    ?assert(binary:match(Description, <<"monthly fee">>) =/= nomatch),
    ok.

apply_template_interest(_Config) ->
    AccountId = <<"account-002">>,
    Params = #{amount => 250, currency => 'USD', note => <<"Q1 interest">>},
    {ok, {_Aid, _Amt, _Cur, Description}} = cb_posting_templates:apply_template(interest, AccountId, Params),
    ?assert(binary:match(Description, <<"Interest charge:">>) =/= nomatch),
    ok.

apply_template_missing_fields(_Config) ->
    AccountId = <<"account-003">>,
    {error, Reason} = cb_posting_templates:apply_template(fee, AccountId, #{amount => 100}),
    ?assertEqual(missing_required_field, Reason),
    ok.

apply_template_not_found(_Config) ->
    AccountId = <<"account-004">>,
    Params = #{amount => 100, currency => 'USD', note => <<"test">>},
    {error, Reason} = cb_posting_templates:apply_template(unknown_template, AccountId, Params),
    ?assertEqual(template_not_found, Reason),
    ok.
