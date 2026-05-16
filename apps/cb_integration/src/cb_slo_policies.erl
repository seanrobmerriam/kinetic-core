%% @doc SLO objectives and alert policy evaluation for critical API paths.
%%
%% This module defines runtime SLO/SLA targets and evaluates live metrics
%% against those targets. It emits objective status snapshots and alert
%% candidates that can be consumed by operations tooling.
-module(cb_slo_policies).

-export([
    critical_path/2,
    evaluate/0,
    targets/0
]).

-define(SLO_KEY, request_slo_path).

-spec critical_path(binary(), binary()) -> auth_login | funds_transfer | cash_movement | core_reads | undefined.
critical_path(<<"POST">>, <<"/api/v1/auth/login">>) -> auth_login;
critical_path(<<"POST">>, <<"/api/v1/transactions/transfer">>) -> funds_transfer;
critical_path(<<"POST">>, <<"/api/v1/transactions/deposit">>) -> cash_movement;
critical_path(<<"POST">>, <<"/api/v1/transactions/withdraw">>) -> cash_movement;
critical_path(<<"GET">>, Path) ->
    case is_core_read_path(Path) of
        true -> core_reads;
        false -> undefined
    end;
critical_path(_, _) ->
    undefined.

-spec targets() -> [map()].
targets() ->
    [
        #{
            id => auth_login,
            sli => availability,
            target_pct => 99.95,
            min_sample_size => 20,
            description => <<"Authentication login success ratio">>
        },
        #{
            id => funds_transfer,
            sli => availability,
            target_pct => 99.90,
            min_sample_size => 20,
            description => <<"Transfer processing success ratio">>
        },
        #{
            id => cash_movement,
            sli => availability,
            target_pct => 99.90,
            min_sample_size => 20,
            description => <<"Deposit and withdrawal success ratio">>
        },
        #{
            id => core_reads,
            sli => availability,
            target_pct => 99.50,
            min_sample_size => 50,
            description => <<"Core read API success ratio">>
        },
        #{
            id => platform_dependencies,
            sli => dependency_health,
            target_status => ok,
            max_latency_ms => 250,
            description => <<"Dependency health and latency budget">>
        }
    ].

-spec evaluate() -> #{generated_at_ms := integer(), objectives := [map()], alerts := [map()]}.
evaluate() ->
    ObjectiveTargets = targets(),
    Objectives = [evaluate_target(T) || T <- ObjectiveTargets],
    Alerts = lists:flatten([objective_alerts(O) || O <- Objectives]),
    #{
        generated_at_ms => erlang:system_time(millisecond),
        objectives => Objectives,
        alerts => Alerts
    }.

-spec evaluate_target(map()) -> map().
evaluate_target(#{id := platform_dependencies} = Target) ->
    Checks = dependency_checks(),
    Statuses = [maps:get(status, C) || C <- Checks],
    Latencies = [maps:get(latency_ms, C) || C <- Checks],
    MaxLatency = case Latencies of
        [] -> 0;
        _ -> lists:max(Latencies)
    end,
    HealthState = case lists:member(unhealthy, Statuses) of
        true -> unhealthy;
        false ->
            case lists:member(degraded, Statuses) of
                true -> degraded;
                false -> ok
            end
    end,
    LatencyBudget = maps:get(max_latency_ms, Target),
    ObjectiveStatus = case HealthState =:= ok andalso MaxLatency =< LatencyBudget of
        true -> healthy;
        false -> breached
    end,
    Target#{
        status => ObjectiveStatus,
        value => #{
            dependency_status => HealthState,
            max_latency_ms => MaxLatency,
            checks => Checks
        }
    };
evaluate_target(Target) ->
    Id = maps:get(id, Target),
    Total = cb_metrics_counter:get({slo, Id, total}),
    Error5xx = cb_metrics_counter:get({slo, Id, error_5xx}),
    Availability = availability_pct(Total, Error5xx),
    MinSample = maps:get(min_sample_size, Target),
    ObjectiveStatus = case Total < MinSample of
        true -> insufficient_data;
        false ->
            case Availability >= maps:get(target_pct, Target) of
                true -> healthy;
                false -> breached
            end
    end,
    Target#{
        status => ObjectiveStatus,
        value => #{
            availability_pct => Availability,
            total_requests => Total,
            error_5xx => Error5xx
        }
    }.

-spec objective_alerts(map()) -> [map()].
objective_alerts(#{id := Id, status := healthy}) ->
    [#{
        alert_id => build_alert_id(Id, resolved),
        objective => Id,
        severity => info,
        state => resolved,
        message => <<"Objective within target">>
    }];
objective_alerts(#{id := Id, status := insufficient_data}) ->
    [#{
        alert_id => build_alert_id(Id, insufficient_data),
        objective => Id,
        severity => info,
        state => monitoring,
        message => <<"Insufficient sample size for policy enforcement">>
    }];
objective_alerts(#{id := platform_dependencies, value := Value}) ->
    DepStatus = maps:get(dependency_status, Value),
    MaxLatency = maps:get(max_latency_ms, Value),
    Severity = case DepStatus of
        unhealthy -> critical;
        degraded -> warning;
        ok -> warning
    end,
    [#{
        alert_id => build_alert_id(platform_dependencies, DepStatus),
        objective => platform_dependencies,
        severity => Severity,
        state => firing,
        message => iolist_to_binary([
            <<"Dependency objective breached: status=">>, atom_to_binary(DepStatus, utf8),
            <<", max_latency_ms=">>, integer_to_binary(MaxLatency)
        ])
    }];
objective_alerts(#{id := Id, target_pct := TargetPct, value := Value}) ->
    Availability = maps:get(availability_pct, Value),
    Gap = TargetPct - Availability,
    Severity = case Gap >= 2.0 of
        true -> critical;
        false -> warning
    end,
    [#{
        alert_id => build_alert_id(Id, breached),
        objective => Id,
        severity => Severity,
        state => firing,
        message => iolist_to_binary([
            <<"Availability below target: ">>, float_to_binary(Availability, [{decimals, 3}]),
            <<"% < ">>, float_to_binary(TargetPct, [{decimals, 3}]), <<"%">>
        ])
    }].

-spec availability_pct(non_neg_integer(), non_neg_integer()) -> float().
availability_pct(0, _Error5xx) -> 100.0;
availability_pct(Total, Error5xx) ->
    ((Total - Error5xx) / Total) * 100.0.

-spec dependency_checks() -> [map()].
dependency_checks() ->
    [
        dependency_check(<<"mnesia">>, fun() -> mnesia:system_info(is_running) =:= yes end),
        dependency_check(<<"ledger_table">>, fun() -> table_exists(ledger_entry) end),
        dependency_check(<<"transaction_table">>, fun() -> table_exists(transaction) end),
        dependency_check(<<"auth_session_table">>, fun() -> table_exists(auth_session) end)
    ].

-spec dependency_check(binary(), fun(() -> boolean())) -> map().
dependency_check(Name, CheckFun) ->
    Start = erlang:monotonic_time(millisecond),
    Status = try
        case CheckFun() of
            true -> ok;
            false -> degraded
        end
    catch
        _:_ -> unhealthy
    end,
    #{
        service => Name,
        status => Status,
        latency_ms => erlang:monotonic_time(millisecond) - Start
    }.

-spec table_exists(atom()) -> boolean().
table_exists(Table) ->
    Lists = mnesia:system_info(tables),
    lists:member(Table, Lists).

-spec is_core_read_path(binary()) -> boolean().
is_core_read_path(Path) ->
    has_prefix(Path, <<"/api/v1/accounts">>) orelse
    has_prefix(Path, <<"/api/v1/transactions">>) orelse
    has_prefix(Path, <<"/api/v1/ledger">>) orelse
    has_prefix(Path, <<"/api/v1/parties">>).

-spec has_prefix(binary(), binary()) -> boolean().
has_prefix(Bin, Prefix) when is_binary(Bin), is_binary(Prefix) ->
    PrefixSize = byte_size(Prefix),
    BinSize = byte_size(Bin),
    case BinSize >= PrefixSize of
        true -> binary:part(Bin, 0, PrefixSize) =:= Prefix;
        false -> false
    end.

-spec build_alert_id(atom(), atom()) -> binary().
build_alert_id(Objective, State) ->
    iolist_to_binary([
        atom_to_binary(Objective, utf8),
        <<":">>,
        atom_to_binary(State, utf8)
    ]).
