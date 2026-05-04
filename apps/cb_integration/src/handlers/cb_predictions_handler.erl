%% @doc HTTP handler for predictions (TASK-076).
%%
%% Routes:
%%   POST /api/v1/analytics/predictions/churn
%%     body: {entity_id, features: #{...}, features_used: [..]}
%%   POST /api/v1/analytics/predictions/anomaly
%%     body: {entity_id, sample, baseline_mean, baseline_stddev}
%%   GET  /api/v1/analytics/predictions/:kind   (churn|anomaly) — list by kind
%%   GET  /api/v1/analytics/predictions/by-entity/:entity_id
-module(cb_predictions_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").
-include_lib("cb_analytics/include/cb_analytics.hrl").

-export([init/2]).

init(Req, State) ->
    Method   = cowboy_req:method(Req),
    Resource = cowboy_req:binding(resource, Req),
    Id       = cowboy_req:binding(id, Req),
    handle(Method, Resource, Id, Req, State).

handle(<<"POST">>, <<"churn">>, undefined, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{entity_id := E, features := F, features_used := Used}, _}
                when is_map(F), is_list(Used) ->
            FloatMap = maps:map(fun(_, V) -> to_float(V) end, F),
            {ok, Id, Score, Conf, Bnd} =
                cb_predictions:score_churn(E, FloatMap, Used),
            reply(201, #{prediction_id => Id, score => Score,
                         confidence => Conf, confidence_band => Bnd},
                  Req2, State);
        _ ->
            error_reply(400, <<"Missing required fields">>, Req2, State)
    end;

handle(<<"POST">>, <<"anomaly">>, undefined, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{entity_id := E, sample := S,
               baseline_mean := M, baseline_stddev := SD}, _} ->
            {ok, Id, Score, Conf, Bnd} =
                cb_predictions:score_anomaly(E, to_float(S),
                                             {to_float(M), to_float(SD)}),
            reply(201, #{prediction_id => Id, score => Score,
                         confidence => Conf, confidence_band => Bnd},
                  Req2, State);
        _ ->
            error_reply(400, <<"Missing required fields">>, Req2, State)
    end;

handle(<<"GET">>, Kind, undefined, Req, State)
        when Kind =:= <<"churn">>; Kind =:= <<"anomaly">> ->
    KindAtom = case Kind of
        <<"churn">>   -> churn;
        <<"anomaly">> -> anomaly
    end,
    Ps = cb_predictions:list_by_kind(KindAtom),
    reply(200, #{predictions => [pred_to_map(P) || P <- Ps]}, Req, State);

handle(<<"GET">>, <<"by-entity">>, EntityId, Req, State) ->
    Ps = cb_predictions:list_for_entity(EntityId),
    reply(200, #{predictions => [pred_to_map(P) || P <- Ps]}, Req, State);

handle(_, _, _, Req, State) ->
    error_reply(405, <<"Method not allowed">>, Req, State).

to_float(N) when is_integer(N) -> N * 1.0;
to_float(F) when is_float(F)   -> F.

pred_to_map(P) ->
    #{prediction_id   => P#prediction_score.prediction_id,
      kind            => P#prediction_score.kind,
      entity_id       => P#prediction_score.entity_id,
      score           => P#prediction_score.score,
      confidence      => P#prediction_score.confidence,
      confidence_band => P#prediction_score.confidence_band,
      features_used   => P#prediction_score.features_used,
      computed_at     => P#prediction_score.computed_at}.

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
