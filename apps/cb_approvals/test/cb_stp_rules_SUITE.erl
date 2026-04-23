%% @doc CT tests for cb_stp_rules (TASK-050 — rule-based routing).
-module(cb_stp_rules_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    create_rule_ok/1,
    get_rule_not_found/1,
    list_rules_sorted_by_priority/1,
    update_rule_fields/1,
    delete_rule_ok/1,
    enable_disable_rule/1,
    evaluate_order_no_rules_is_no_match/1,
    evaluate_order_amount_rule_matches/1,
    evaluate_order_first_match_wins/1,
    evaluate_order_disabled_rule_skipped/1
]).

all() ->
    [
        create_rule_ok,
        get_rule_not_found,
        list_rules_sorted_by_priority,
        update_rule_fields,
        delete_rule_ok,
        enable_disable_rule,
        evaluate_order_no_rules_is_no_match,
        evaluate_order_amount_rule_matches,
        evaluate_order_first_match_wins,
        evaluate_order_disabled_rule_skipped
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
    mnesia:clear_table(stp_routing_rule),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

make_order(Amount) ->
    #payment_order{
        payment_id        = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
        idempotency_key   = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
        party_id          = <<"party-test">>,
        source_account_id = <<"acc-test">>,
        dest_account_id   = <<"acc-dest">>,
        amount            = Amount,
        currency          = 'USD',
        description       = <<"Test order">>,
        status            = initiated,
        stp_decision      = undefined,
        failure_reason    = undefined,
        retry_count       = 0,
        created_at        = erlang:system_time(millisecond),
        updated_at        = erlang:system_time(millisecond)
    }.

%%% ---------------------------------------------------------------- TESTS ---

create_rule_ok(_Config) ->
    {ok, Rule} = cb_stp_rules:create_rule(<<"High amount">>, 10, amount,
                                           #{threshold => 500_000}, exception),
    ?assertMatch(#{rule_id := _, name := <<"High amount">>, priority := 10,
                   condition_type := amount, action := exception, enabled := true},
                 rule_to_map(Rule)).

get_rule_not_found(_Config) ->
    ?assertEqual({error, not_found}, cb_stp_rules:get_rule(<<"no-such-id">>)).

list_rules_sorted_by_priority(_Config) ->
    {ok, _} = cb_stp_rules:create_rule(<<"B">>, 20, amount, #{threshold => 1000}, exception),
    {ok, _} = cb_stp_rules:create_rule(<<"A">>, 5,  amount, #{threshold => 2000}, exception),
    {ok, _} = cb_stp_rules:create_rule(<<"C">>, 15, amount, #{threshold => 3000}, exception),
    Rules = cb_stp_rules:list_rules(),
    Priorities = [R#stp_routing_rule.priority || R <- Rules],
    ?assertEqual(Priorities, lists:sort(Priorities)).

update_rule_fields(_Config) ->
    {ok, Rule} = cb_stp_rules:create_rule(<<"Old">>, 10, amount, #{threshold => 100}, exception),
    {ok, Updated} = cb_stp_rules:update_rule(Rule#stp_routing_rule.rule_id,
                                              #{name => <<"New">>, priority => 5}),
    ?assertEqual(<<"New">>, Updated#stp_routing_rule.name),
    ?assertEqual(5, Updated#stp_routing_rule.priority).

delete_rule_ok(_Config) ->
    {ok, Rule} = cb_stp_rules:create_rule(<<"Del">>, 10, amount, #{threshold => 100}, exception),
    Id = Rule#stp_routing_rule.rule_id,
    ?assertEqual(ok, cb_stp_rules:delete_rule(Id)),
    ?assertEqual({error, not_found}, cb_stp_rules:get_rule(Id)).

enable_disable_rule(_Config) ->
    {ok, Rule} = cb_stp_rules:create_rule(<<"Toggle">>, 1, amount, #{threshold => 100}, exception),
    Id = Rule#stp_routing_rule.rule_id,
    {ok, Disabled} = cb_stp_rules:disable_rule(Id),
    ?assertEqual(false, Disabled#stp_routing_rule.enabled),
    {ok, Enabled} = cb_stp_rules:enable_rule(Id),
    ?assertEqual(true, Enabled#stp_routing_rule.enabled).

evaluate_order_no_rules_is_no_match(_Config) ->
    Order = make_order(50_000),
    ?assertEqual(no_match, cb_stp_rules:evaluate_order(Order)).

evaluate_order_amount_rule_matches(_Config) ->
    {ok, _} = cb_stp_rules:create_rule(<<"Block large">>, 1, amount,
                                        #{threshold => 100_000}, exception),
    SmallOrder = make_order(50_000),
    LargeOrder = make_order(200_000),
    ?assertEqual(no_match, cb_stp_rules:evaluate_order(SmallOrder)),
    ?assertEqual(exception, cb_stp_rules:evaluate_order(LargeOrder)).

evaluate_order_first_match_wins(_Config) ->
    {ok, _} = cb_stp_rules:create_rule(<<"Prio 1">>, 1, amount,
                                        #{threshold => 100_000}, straight_through),
    {ok, _} = cb_stp_rules:create_rule(<<"Prio 2">>, 2, amount,
                                        #{threshold => 50_000}, exception),
    Order = make_order(200_000),
    %% Both rules match (200k > 100k and 200k > 50k) but priority 1 (straight_through) wins
    ?assertEqual(straight_through, cb_stp_rules:evaluate_order(Order)).

evaluate_order_disabled_rule_skipped(_Config) ->
    {ok, Rule} = cb_stp_rules:create_rule(<<"Disabled">>, 1, amount,
                                           #{threshold => 1000}, exception),
    {ok, _} = cb_stp_rules:disable_rule(Rule#stp_routing_rule.rule_id),
    Order = make_order(50_000),
    ?assertEqual(no_match, cb_stp_rules:evaluate_order(Order)).

rule_to_map(#stp_routing_rule{
    rule_id = Id, name = Name, priority = P,
    condition_type = CT, action = A, enabled = E
}) ->
    #{rule_id => Id, name => Name, priority => P,
      condition_type => CT, action => A, enabled => E}.
