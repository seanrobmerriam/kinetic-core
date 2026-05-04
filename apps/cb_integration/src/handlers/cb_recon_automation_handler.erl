%% @doc HTTP handler for reconciliation automation (TASK-071).
%%
%% Routes:
%%   GET  /api/v1/recon/runs                            — list runs
%%   POST /api/v1/recon/runs                            — start run
%%   GET  /api/v1/recon/runs/:run_id                    — get run
%%   POST /api/v1/recon/runs/:run_id/:action            — complete | fail
%%   GET  /api/v1/recon/runs/:run_id/alerts             — list run alerts
%%   POST /api/v1/recon/runs/:run_id/alerts             — record divergence
%%   GET  /api/v1/recon/alerts/open                     — list open alerts
%%   POST /api/v1/recon/alerts/:alert_id/acknowledge    — acknowledge alert
-module(cb_recon_automation_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

init(Req, State) ->
    Method   = cowboy_req:method(Req),
    Resource = cowboy_req:binding(resource, Req),
    Id       = cowboy_req:binding(id, Req),
    Action   = cowboy_req:binding(action, Req),
    handle(Method, Resource, Id, Action, Req, State).

handle(<<"GET">>, <<"runs">>, undefined, undefined, Req, State) ->
    Runs = cb_recon_automation:list_runs(),
    Body = jsone:encode(#{runs => [run_to_map(R) || R <- Runs]}),
    R = cowboy_req:reply(200, headers(), Body, Req),
    {ok, R, State};

handle(<<"POST">>, <<"runs">>, undefined, undefined, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{scope := Scope}, _} ->
            case cb_recon_automation:start_run(Scope) of
                {ok, RunId} ->
                    R = cowboy_req:reply(201, headers(),
                            jsone:encode(#{run_id => RunId}), Req2),
                    {ok, R, State};
                {error, Reason} ->
                    error_reply(400, Reason, Req2, State)
            end;
        _ ->
            error_reply(400, <<"Missing required field: scope">>, Req2, State)
    end;

handle(<<"GET">>, <<"runs">>, RunId, undefined, Req, State) ->
    case cb_recon_automation:get_run(RunId) of
        {ok, Run}          -> reply_json(200, run_to_map(Run), Req, State);
        {error, not_found} -> error_reply(404, <<"Run not found">>, Req, State)
    end;

handle(<<"POST">>, <<"runs">>, RunId, <<"complete">>, Req, State) ->
    transition_reply(cb_recon_automation:complete_run(RunId), Req, State);
handle(<<"POST">>, <<"runs">>, RunId, <<"fail">>, Req, State) ->
    transition_reply(cb_recon_automation:fail_run(RunId), Req, State);

handle(<<"GET">>, <<"runs">>, RunId, <<"alerts">>, Req, State) ->
    Alerts = cb_recon_automation:list_alerts(RunId),
    reply_json(200, #{alerts => [alert_to_map(A) || A <- Alerts]}, Req, State);

handle(<<"POST">>, <<"runs">>, RunId, <<"alerts">>, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{severity := SevBin, details := Details}, _} when is_map(Details) ->
            case parse_severity(SevBin) of
                {ok, Sev} ->
                    case cb_recon_automation:record_divergence(RunId, Sev, Details) of
                        {ok, AlertId} ->
                            R = cowboy_req:reply(201, headers(),
                                    jsone:encode(#{alert_id => AlertId}), Req2),
                            {ok, R, State};
                        {error, not_found} ->
                            error_reply(404, <<"Run not found">>, Req2, State);
                        {error, Reason} ->
                            error_reply(400, Reason, Req2, State)
                    end;
                error ->
                    error_reply(400, <<"Invalid severity">>, Req2, State)
            end;
        _ ->
            error_reply(400,
                <<"Missing required fields: severity, details">>, Req2, State)
    end;

handle(<<"GET">>, <<"alerts">>, <<"open">>, undefined, Req, State) ->
    Alerts = cb_recon_automation:list_open_alerts(),
    reply_json(200, #{alerts => [alert_to_map(A) || A <- Alerts]}, Req, State);

handle(<<"POST">>, <<"alerts">>, AlertId, <<"acknowledge">>, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    By = case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{by := B}, _} when is_binary(B) -> B;
        _                                     -> <<"system">>
    end,
    case cb_recon_automation:acknowledge_alert(AlertId, By) of
        ok ->
            R = cowboy_req:reply(200, headers(),
                    jsone:encode(#{status => <<"acknowledged">>}), Req2),
            {ok, R, State};
        {error, not_found} ->
            error_reply(404, <<"Alert not found">>, Req2, State);
        {error, Reason} ->
            error_reply(400, Reason, Req2, State)
    end;

handle(_, _, _, _, Req, State) ->
    error_reply(405, <<"Method not allowed">>, Req, State).

parse_severity(<<"info">>)     -> {ok, info};
parse_severity(<<"warning">>)  -> {ok, warning};
parse_severity(<<"critical">>) -> {ok, critical};
parse_severity(_)              -> error.

transition_reply(ok, Req, State) ->
    R = cowboy_req:reply(200, headers(),
            jsone:encode(#{status => <<"updated">>}), Req),
    {ok, R, State};
transition_reply({error, not_found}, Req, State) ->
    error_reply(404, <<"Run not found">>, Req, State);
transition_reply({error, Reason}, Req, State) ->
    error_reply(400, Reason, Req, State).

reply_json(Code, Map, Req, State) ->
    R = cowboy_req:reply(Code, headers(), jsone:encode(Map), Req),
    {ok, R, State}.

run_to_map(R) ->
    #{run_id            => R#recon_run.run_id,
      scope             => R#recon_run.scope,
      status            => R#recon_run.status,
      started_at        => R#recon_run.started_at,
      completed_at      => R#recon_run.completed_at,
      divergences_count => R#recon_run.divergences_count}.

alert_to_map(A) ->
    #{alert_id        => A#divergence_alert.alert_id,
      run_id          => A#divergence_alert.run_id,
      severity        => A#divergence_alert.severity,
      status          => A#divergence_alert.status,
      details         => A#divergence_alert.details,
      created_at      => A#divergence_alert.created_at,
      acknowledged_at => A#divergence_alert.acknowledged_at,
      acknowledged_by => A#divergence_alert.acknowledged_by}.

headers() ->
    #{<<"content-type">> => <<"application/json">>}.

error_reply(Code, Reason, Req, State) when is_atom(Reason) ->
    error_reply(Code, atom_to_binary(Reason, utf8), Req, State);
error_reply(Code, Reason, Req, State) ->
    R = cowboy_req:reply(Code, headers(),
            jsone:encode(#{error => Reason}), Req),
    {ok, R, State}.
