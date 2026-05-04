%% @doc Horizontal Scaling and Capacity-Triggered Autoscaling (TASK-068).
%%
%% Maintains named scaling rules.  Each rule watches a metric_name and fires
%% when a capacity_sample exceeds (scale_out) or falls below (scale_in) the
%% configured threshold.
%%
%% Callers record metric samples with record_metric/2 and then call
%% evaluate_rules/0 to obtain a list of currently triggered rules.
-module(cb_scaling).
-compile({parse_transform, ms_transform}).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    add_rule/1,
    get_rule/1,
    list_rules/0,
    update_rule/2,
    delete_rule/1,
    enable_rule/1,
    disable_rule/1,
    record_metric/2,
    latest_sample/1,
    evaluate_rules/0
]).

-spec add_rule(map()) -> {ok, uuid()} | {error, term()}.
add_rule(#{name := Name, metric_name := Metric,
           threshold := Threshold, direction := Direction,
           cooldown_seconds := Cooldown}) ->
    RuleId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
    Now    = erlang:system_time(millisecond),
    Record = #scaling_rule{
        rule_id           = RuleId,
        name              = Name,
        metric_name       = Metric,
        threshold         = Threshold,
        direction         = Direction,
        cooldown_seconds  = Cooldown,
        enabled           = true,
        last_triggered_at = undefined,
        created_at        = Now,
        updated_at        = Now
    },
    case mnesia:transaction(fun() -> mnesia:write(Record) end) of
        {atomic, ok}     -> {ok, RuleId};
        {aborted, Reason} -> {error, Reason}
    end.

-spec get_rule(uuid()) -> {ok, #scaling_rule{}} | {error, not_found}.
get_rule(RuleId) ->
    case mnesia:dirty_read(scaling_rule, RuleId) of
        [R] -> {ok, R};
        []  -> {error, not_found}
    end.

-spec list_rules() -> [#scaling_rule{}].
list_rules() ->
    {atomic, Rules} = mnesia:transaction(fun() ->
        mnesia:match_object(#scaling_rule{_ = '_'})
    end),
    Rules.

-spec update_rule(uuid(), map()) -> ok | {error, not_found}.
update_rule(RuleId, Params) ->
    Now = erlang:system_time(millisecond),
    case mnesia:transaction(fun() ->
        case mnesia:read(scaling_rule, RuleId) of
            [] -> {error, not_found};
            [R] ->
                Updated = R#scaling_rule{
                    name             = maps:get(name, Params, R#scaling_rule.name),
                    metric_name      = maps:get(metric_name, Params, R#scaling_rule.metric_name),
                    threshold        = maps:get(threshold, Params, R#scaling_rule.threshold),
                    direction        = maps:get(direction, Params, R#scaling_rule.direction),
                    cooldown_seconds = maps:get(cooldown_seconds, Params, R#scaling_rule.cooldown_seconds),
                    updated_at       = Now
                },
                mnesia:write(Updated),
                ok
        end
    end) of
        {atomic, Result}  -> Result;
        {aborted, Reason} -> {error, Reason}
    end.

-spec delete_rule(uuid()) -> ok | {error, not_found}.
delete_rule(RuleId) ->
    case mnesia:transaction(fun() ->
        case mnesia:read(scaling_rule, RuleId) of
            []  -> {error, not_found};
            [_] -> mnesia:delete({scaling_rule, RuleId}), ok
        end
    end) of
        {atomic, Result}  -> Result;
        {aborted, Reason} -> {error, Reason}
    end.

-spec enable_rule(uuid()) -> ok | {error, not_found}.
enable_rule(RuleId) -> set_enabled(RuleId, true).

-spec disable_rule(uuid()) -> ok | {error, not_found}.
disable_rule(RuleId) -> set_enabled(RuleId, false).

-spec record_metric(binary(), number()) -> {ok, uuid()}.
record_metric(MetricName, Value) ->
    SampleId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
    Now = erlang:system_time(millisecond),
    Sample = #capacity_sample{
        sample_id   = SampleId,
        metric_name = MetricName,
        value       = Value,
        node_id     = undefined,
        recorded_at = Now
    },
    {atomic, ok} = mnesia:transaction(fun() -> mnesia:write(Sample) end),
    {ok, SampleId}.

-spec latest_sample(binary()) -> {ok, number()} | {error, no_data}.
latest_sample(MetricName) ->
    MS = ets:fun2ms(fun(#capacity_sample{metric_name = MN} = S)
                        when MN =:= MetricName -> S end),
    {atomic, Samples} = mnesia:transaction(fun() ->
        mnesia:select(capacity_sample, MS)
    end),
    case lists:sort(fun(A, B) ->
        A#capacity_sample.recorded_at >= B#capacity_sample.recorded_at end,
        Samples) of
        []    -> {error, no_data};
        [S|_] -> {ok, S#capacity_sample.value}
    end.

%% @doc Evaluate all enabled rules against the latest observed metric values.
%% Returns a list of {RuleId, direction} pairs for rules whose thresholds
%% are currently breached and are not within their cooldown window.
-spec evaluate_rules() -> [{uuid(), scaling_direction()}].
evaluate_rules() ->
    Rules = [R || R <- list_rules(), R#scaling_rule.enabled =:= true],
    Now = erlang:system_time(millisecond),
    lists:filtermap(fun(Rule) ->
        case latest_sample(Rule#scaling_rule.metric_name) of
            {error, no_data} ->
                false;
            {ok, Value} ->
                Triggered = case Rule#scaling_rule.direction of
                    scale_out -> Value > Rule#scaling_rule.threshold;
                    scale_in  -> Value < Rule#scaling_rule.threshold
                end,
                InCooldown = case Rule#scaling_rule.last_triggered_at of
                    undefined -> false;
                    TS ->
                        ElapsedSec = (Now - TS) div 1000,
                        ElapsedSec < Rule#scaling_rule.cooldown_seconds
                end,
                if Triggered andalso not InCooldown ->
                    %% Record trigger timestamp
                    mnesia:transaction(fun() ->
                        case mnesia:read(scaling_rule, Rule#scaling_rule.rule_id) of
                            [R] -> mnesia:write(R#scaling_rule{last_triggered_at = Now});
                            []  -> ok
                        end
                    end),
                    {true, {Rule#scaling_rule.rule_id, Rule#scaling_rule.direction}};
                true ->
                    false
                end
        end
    end, Rules).

%%--------------------------------------------------------------------
%% Internal
%%--------------------------------------------------------------------

set_enabled(RuleId, Enabled) ->
    case mnesia:transaction(fun() ->
        case mnesia:read(scaling_rule, RuleId) of
            []  -> {error, not_found};
            [R] -> mnesia:write(R#scaling_rule{enabled = Enabled}), ok
        end
    end) of
        {atomic, Result}  -> Result;
        {aborted, Reason} -> {error, Reason}
    end.
