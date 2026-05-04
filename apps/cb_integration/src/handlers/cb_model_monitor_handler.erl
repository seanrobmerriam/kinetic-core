%% @doc HTTP handler for model monitoring + retraining (TASK-077).
%%
%% Routes:
%%   GET  /api/v1/analytics/monitors
%%   POST /api/v1/analytics/monitors
%%   GET  /api/v1/analytics/monitors/:id
%%   POST /api/v1/analytics/monitors/:id/samples
%%   GET  /api/v1/analytics/monitors/:id/alerts
%%   GET  /api/v1/analytics/triggers
%%   POST /api/v1/analytics/triggers
%%   POST /api/v1/analytics/triggers/:id/:action  (acknowledge|complete)
-module(cb_model_monitor_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").
-include_lib("cb_analytics/include/cb_analytics.hrl").

-export([init/2]).

init(Req, State) ->
    Method   = cowboy_req:method(Req),
    Resource = case cowboy_req:binding(resource, Req) of
        undefined -> proplists:get_value(resource, State);
        R         -> R
    end,
    Id       = cowboy_req:binding(id, Req),
    Action   = cowboy_req:binding(action, Req),
    handle(Method, Resource, Id, Action, Req, State).

handle(<<"GET">>, <<"monitors">>, undefined, undefined, Req, State) ->
    Ms = cb_model_monitor:list_monitors(),
    reply(200, #{monitors => [mon_to_map(M) || M <- Ms]}, Req, State);

handle(<<"POST">>, <<"monitors">>, undefined, undefined, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{model_name := MN, feature_key := FK,
               baseline_mean := M, baseline_stddev := SD,
               drift_threshold := T}, _} ->
            case cb_model_monitor:register_monitor(
                    MN, FK, {to_float(M), to_float(SD)}, to_float(T)) of
                {ok, Id}        -> reply(201, #{monitor_id => Id}, Req2, State);
                {error, Reason} -> error_reply(400, Reason, Req2, State)
            end;
        _ ->
            error_reply(400, <<"Missing required fields">>, Req2, State)
    end;

handle(<<"GET">>, <<"monitors">>, Id, undefined, Req, State) ->
    case cb_model_monitor:get_monitor(Id) of
        {ok, M}            -> reply(200, mon_to_map(M), Req, State);
        {error, not_found} -> error_reply(404, <<"Monitor not found">>, Req, State)
    end;

handle(<<"POST">>, <<"monitors">>, Id, <<"samples">>, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{observed_mean := OM, sample_size := N}, _}
                when is_integer(N), N >= 0 ->
            case cb_model_monitor:record_sample(Id, to_float(OM), N) of
                {ok, Status, Drift} ->
                    reply(200,
                          #{status => Status, drift_score => Drift},
                          Req2, State);
                {error, not_found} ->
                    error_reply(404, <<"Monitor not found">>, Req2, State)
            end;
        _ ->
            error_reply(400, <<"Missing required fields">>, Req2, State)
    end;

handle(<<"GET">>, <<"monitors">>, Id, <<"alerts">>, Req, State) ->
    Alerts = cb_model_monitor:list_alerts_for_monitor(Id),
    reply(200, #{alerts => [alert_to_map(A) || A <- Alerts]}, Req, State);

handle(<<"GET">>, <<"triggers">>, undefined, undefined, Req, State) ->
    Ts = cb_model_monitor:list_triggers(),
    reply(200, #{triggers => [trig_to_map(T) || T <- Ts]}, Req, State);

handle(<<"POST">>, <<"triggers">>, undefined, undefined, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{model_name := MN, reason := R, alert_ids := As}, _}
                when is_list(As) ->
            {ok, Id} = cb_model_monitor:raise_retraining(MN, R, As),
            reply(201, #{trigger_id => Id}, Req2, State);
        _ ->
            error_reply(400, <<"Missing required fields">>, Req2, State)
    end;

handle(<<"POST">>, <<"triggers">>, Id, Action, Req, State)
        when Action =:= <<"acknowledge">>; Action =:= <<"complete">> ->
    Result = case Action of
        <<"acknowledge">> -> cb_model_monitor:acknowledge_trigger(Id);
        <<"complete">>    -> cb_model_monitor:complete_trigger(Id)
    end,
    case Result of
        ok                          -> reply(200, #{status => ok}, Req, State);
        {error, not_found}          -> error_reply(404, <<"Trigger not found">>,
                                                   Req, State);
        {error, invalid_transition} -> error_reply(409,
                                          <<"Invalid transition">>,
                                          Req, State)
    end;

handle(_, _, _, _, Req, State) ->
    error_reply(405, <<"Method not allowed">>, Req, State).

to_float(N) when is_integer(N) -> N * 1.0;
to_float(F) when is_float(F)   -> F.

mon_to_map(M) ->
    #{monitor_id      => M#model_monitor.monitor_id,
      model_name      => M#model_monitor.model_name,
      feature_key     => M#model_monitor.feature_key,
      baseline_mean   => M#model_monitor.baseline_mean,
      baseline_stddev => M#model_monitor.baseline_stddev,
      drift_threshold => M#model_monitor.drift_threshold,
      status          => M#model_monitor.status,
      created_at      => M#model_monitor.created_at,
      updated_at      => M#model_monitor.updated_at}.

alert_to_map(A) ->
    #{alert_id      => A#drift_alert.alert_id,
      monitor_id    => A#drift_alert.monitor_id,
      drift_score   => A#drift_alert.drift_score,
      severity      => A#drift_alert.severity,
      observed_mean => A#drift_alert.observed_mean,
      sample_size   => A#drift_alert.sample_size,
      detected_at   => A#drift_alert.detected_at}.

trig_to_map(T) ->
    #{trigger_id => T#retraining_trigger.trigger_id,
      model_name => T#retraining_trigger.model_name,
      reason     => T#retraining_trigger.reason,
      alert_ids  => T#retraining_trigger.alert_ids,
      status     => T#retraining_trigger.status,
      created_at => T#retraining_trigger.created_at,
      updated_at => T#retraining_trigger.updated_at}.

reply(Code, Body, Req, State) ->
    R = cowboy_req:reply(Code, headers(), jsone:encode(Body), Req),
    {ok, R, State}.

headers() ->
    #{<<"content-type">> => <<"application/json">>}.

error_reply(Code, Reason, Req, State) when is_atom(Reason) ->
    error_reply(Code, atom_to_binary(Reason, utf8), Req, State);
error_reply(Code, Reason, Req, State) ->
    R = cowboy_req:reply(Code, headers(),
            jsone:encode(#{error => Reason}), Req),
    {ok, R, State}.
