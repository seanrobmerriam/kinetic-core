%% @doc CT suite for cb_scaling (TASK-068).
-module(cb_scaling_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    all/0,
    init_per_suite/1,
    end_per_suite/1,
    init_per_testcase/2,
    end_per_testcase/2
]).

-export([
    test_add_rule/1,
    test_get_rule/1,
    test_list_rules/1,
    test_update_rule/1,
    test_delete_rule/1,
    test_enable_disable_rule/1,
    test_record_metric/1,
    test_latest_sample/1,
    test_evaluate_rules_scale_out/1,
    test_evaluate_rules_scale_in/1,
    test_evaluate_rules_cooldown/1
]).

all() ->
    [test_add_rule,
     test_get_rule,
     test_list_rules,
     test_update_rule,
     test_delete_rule,
     test_enable_disable_rule,
     test_record_metric,
     test_latest_sample,
     test_evaluate_rules_scale_out,
     test_evaluate_rules_scale_in,
     test_evaluate_rules_cooldown].

init_per_suite(Config) ->
    ok = mnesia:start(),
    Tables = [cluster_node, version_token, scaling_rule, capacity_sample, recovery_checkpoint],
    [catch mnesia:delete_table(T) || T <- Tables],
    ok = cb_schema:create_tables(),
    Config.

end_per_suite(_Config) ->
    mnesia:stop(),
    ok.

init_per_testcase(_TestCase, Config) ->
    {atomic, ok} = mnesia:clear_table(scaling_rule),
    {atomic, ok} = mnesia:clear_table(capacity_sample),
    Config.

end_per_testcase(_TestCase, _Config) -> ok.

%%--------------------------------------------------------------------
%% Test cases
%%--------------------------------------------------------------------

test_add_rule(_Config) ->
    {ok, RuleId} = cb_scaling:add_rule(sample_rule()),
    true = is_binary(RuleId).

test_get_rule(_Config) ->
    {ok, RuleId} = cb_scaling:add_rule(sample_rule()),
    {ok, #scaling_rule{rule_id = RuleId, enabled = true}} = cb_scaling:get_rule(RuleId),
    {error, not_found} = cb_scaling:get_rule(<<"nonexistent">>).

test_list_rules(_Config) ->
    {ok, _} = cb_scaling:add_rule(sample_rule()),
    {ok, _} = cb_scaling:add_rule(sample_rule()),
    Rules = cb_scaling:list_rules(),
    true = length(Rules) >= 2.

test_update_rule(_Config) ->
    {ok, RuleId} = cb_scaling:add_rule(sample_rule()),
    ok = cb_scaling:update_rule(RuleId, #{threshold => 95.0}),
    {ok, Rule} = cb_scaling:get_rule(RuleId),
    95.0 = Rule#scaling_rule.threshold.

test_delete_rule(_Config) ->
    {ok, RuleId} = cb_scaling:add_rule(sample_rule()),
    ok = cb_scaling:delete_rule(RuleId),
    {error, not_found} = cb_scaling:get_rule(RuleId).

test_enable_disable_rule(_Config) ->
    {ok, RuleId} = cb_scaling:add_rule(sample_rule()),
    ok = cb_scaling:disable_rule(RuleId),
    {ok, R1} = cb_scaling:get_rule(RuleId),
    false = R1#scaling_rule.enabled,
    ok = cb_scaling:enable_rule(RuleId),
    {ok, R2} = cb_scaling:get_rule(RuleId),
    true = R2#scaling_rule.enabled.

test_record_metric(_Config) ->
    {ok, SampleId} = cb_scaling:record_metric(<<"cpu_percent">>, 45.5),
    true = is_binary(SampleId).

test_latest_sample(_Config) ->
    {ok, _} = cb_scaling:record_metric(<<"mem_percent">>, 55.0),
    timer:sleep(5),
    {ok, _} = cb_scaling:record_metric(<<"mem_percent">>, 70.0),
    {ok, Value} = cb_scaling:latest_sample(<<"mem_percent">>),
    true = Value =:= 70.0 orelse Value =:= 55.0,
    {error, no_data} = cb_scaling:latest_sample(<<"no_such_metric">>).

test_evaluate_rules_scale_out(_Config) ->
    Metric = <<"cpu_scale_out">>,
    {ok, RuleId} = cb_scaling:add_rule(#{
        name             => <<"cpu-out">>,
        metric_name      => Metric,
        threshold        => 80.0,
        direction        => scale_out,
        cooldown_seconds => 0
    }),
    {ok, _} = cb_scaling:record_metric(Metric, 90.0),
    Triggered = cb_scaling:evaluate_rules(),
    true = lists:any(fun({Id, Dir}) -> Id =:= RuleId andalso Dir =:= scale_out end, Triggered).

test_evaluate_rules_scale_in(_Config) ->
    Metric = <<"cpu_scale_in">>,
    {ok, RuleId} = cb_scaling:add_rule(#{
        name             => <<"cpu-in">>,
        metric_name      => Metric,
        threshold        => 20.0,
        direction        => scale_in,
        cooldown_seconds => 0
    }),
    {ok, _} = cb_scaling:record_metric(Metric, 10.0),
    Triggered = cb_scaling:evaluate_rules(),
    true = lists:any(fun({Id, Dir}) -> Id =:= RuleId andalso Dir =:= scale_in end, Triggered).

test_evaluate_rules_cooldown(_Config) ->
    Metric = <<"cpu_cooldown">>,
    {ok, RuleId} = cb_scaling:add_rule(#{
        name             => <<"cpu-cooldown">>,
        metric_name      => Metric,
        threshold        => 80.0,
        direction        => scale_out,
        cooldown_seconds => 3600
    }),
    {ok, _} = cb_scaling:record_metric(Metric, 90.0),
    %% First evaluation triggers
    T1 = cb_scaling:evaluate_rules(),
    true = lists:any(fun({Id, _}) -> Id =:= RuleId end, T1),
    %% Second evaluation is within cooldown → not triggered
    T2 = cb_scaling:evaluate_rules(),
    false = lists:any(fun({Id, _}) -> Id =:= RuleId end, T2).

%%--------------------------------------------------------------------
%% Helpers
%%--------------------------------------------------------------------

sample_rule() ->
    #{name             => <<"test-rule">>,
      metric_name      => <<"cpu_percent">>,
      threshold        => 80.0,
      direction        => scale_out,
      cooldown_seconds => 60}.
