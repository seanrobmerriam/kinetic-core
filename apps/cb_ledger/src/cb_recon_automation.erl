%% @doc Reconciliation automation and divergence alerting (TASK-071).
%%
%% A recon_run represents one execution of an automated reconciliation
%% over a named scope (e.g. <<"ledger_vs_accounts">>). Divergence findings
%% are recorded as divergence_alert records that operators must acknowledge.
-module(cb_recon_automation).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    start_run/1,
    complete_run/1,
    fail_run/1,
    get_run/1,
    list_runs/0,
    record_divergence/3,
    list_alerts/1,
    list_open_alerts/0,
    acknowledge_alert/2
]).

-spec start_run(binary()) -> {ok, uuid()} | {error, term()}.
start_run(Scope) when is_binary(Scope) ->
    RunId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
    Now = erlang:system_time(millisecond),
    Run = #recon_run{
        run_id            = RunId,
        scope             = Scope,
        status            = running,
        started_at        = Now,
        completed_at      = undefined,
        divergences_count = 0
    },
    case mnesia:transaction(fun() -> mnesia:write(Run) end) of
        {atomic, ok}      -> {ok, RunId};
        {aborted, Reason} -> {error, Reason}
    end;
start_run(_) ->
    {error, invalid_arguments}.

-spec complete_run(uuid()) -> ok | {error, not_found | invalid_status}.
complete_run(RunId) ->
    transition_run(RunId, completed).

-spec fail_run(uuid()) -> ok | {error, not_found | invalid_status}.
fail_run(RunId) ->
    transition_run(RunId, failed).

transition_run(RunId, NewStatus) ->
    F = fun() ->
        case mnesia:read(recon_run, RunId) of
            [R = #recon_run{status = running}] ->
                Now = erlang:system_time(millisecond),
                mnesia:write(R#recon_run{status = NewStatus,
                                          completed_at = Now});
            [_] ->
                {error, invalid_status};
            [] ->
                {error, not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, ok}                       -> ok;
        {atomic, {error, invalid_status}}  -> {error, invalid_status};
        {atomic, {error, not_found}}       -> {error, not_found};
        {aborted, Reason}                  -> {error, Reason}
    end.

-spec get_run(uuid()) -> {ok, #recon_run{}} | {error, not_found}.
get_run(RunId) ->
    case mnesia:dirty_read(recon_run, RunId) of
        [R] -> {ok, R};
        []  -> {error, not_found}
    end.

-spec list_runs() -> [#recon_run{}].
list_runs() ->
    {atomic, Runs} = mnesia:transaction(fun() ->
        mnesia:foldl(fun(R, Acc) -> [R | Acc] end, [], recon_run)
    end),
    lists:sort(fun(A, B) -> A#recon_run.started_at >= B#recon_run.started_at end, Runs).

-spec record_divergence(uuid(), alert_severity(), map()) ->
    {ok, uuid()} | {error, term()}.
record_divergence(RunId, Severity, Details)
        when is_binary(RunId), is_map(Details),
             (Severity =:= info orelse
              Severity =:= warning orelse
              Severity =:= critical) ->
    record_divergence_inner(RunId, Severity, Details);
record_divergence(_, _, _) ->
    {error, invalid_arguments}.

record_divergence_inner(RunId, Severity, Details) ->
    AlertId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
    Now = erlang:system_time(millisecond),
    F = fun() ->
        case mnesia:read(recon_run, RunId) of
            [R] ->
                Alert = #divergence_alert{
                    alert_id        = AlertId,
                    run_id          = RunId,
                    severity        = Severity,
                    status          = open,
                    details         = Details,
                    created_at      = Now,
                    acknowledged_at = undefined,
                    acknowledged_by = undefined
                },
                mnesia:write(Alert),
                mnesia:write(R#recon_run{
                    divergences_count = R#recon_run.divergences_count + 1
                }),
                {ok, AlertId};
            [] ->
                {error, not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, {ok, Id}}            -> {ok, Id};
        {atomic, {error, not_found}}  -> {error, not_found};
        {aborted, Reason}             -> {error, Reason}
    end.

-spec list_alerts(uuid()) -> [#divergence_alert{}].
list_alerts(RunId) ->
    {atomic, Alerts} = mnesia:transaction(fun() ->
        mnesia:index_read(divergence_alert, RunId, run_id)
    end),
    lists:sort(fun(A, B) -> A#divergence_alert.created_at >= B#divergence_alert.created_at end, Alerts).

-spec list_open_alerts() -> [#divergence_alert{}].
list_open_alerts() ->
    {atomic, Alerts} = mnesia:transaction(fun() ->
        mnesia:index_read(divergence_alert, open, status)
    end),
    Alerts.

-spec acknowledge_alert(uuid(), binary()) -> ok | {error, not_found | already_acknowledged}.
acknowledge_alert(AlertId, By) when is_binary(By) ->
    F = fun() ->
        case mnesia:read(divergence_alert, AlertId) of
            [A = #divergence_alert{status = open}] ->
                Now = erlang:system_time(millisecond),
                mnesia:write(A#divergence_alert{
                    status          = acknowledged,
                    acknowledged_at = Now,
                    acknowledged_by = By
                });
            [_] ->
                {error, already_acknowledged};
            [] ->
                {error, not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, ok}                              -> ok;
        {atomic, {error, already_acknowledged}}   -> {error, already_acknowledged};
        {atomic, {error, not_found}}              -> {error, not_found};
        {aborted, Reason}                         -> {error, Reason}
    end;
acknowledge_alert(_, _) ->
    {error, invalid_arguments}.
