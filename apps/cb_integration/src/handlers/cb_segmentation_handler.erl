%% @doc HTTP handler for segmentation + recommendations (TASK-075).
%%
%% Routes (resource = segments|recommendations):
%%   GET  /api/v1/analytics/segments
%%   POST /api/v1/analytics/segments
%%   GET  /api/v1/analytics/segments/:id
%%   POST /api/v1/analytics/segments/:id/:action   (assign|retire)
%%   GET  /api/v1/analytics/recommendations
%%   POST /api/v1/analytics/recommendations
%%   GET  /api/v1/analytics/recommendations/:id
%%   POST /api/v1/analytics/recommendations/:id/:action  (deliver|accept|dismiss)
-module(cb_segmentation_handler).
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

handle(<<"GET">>, <<"segments">>, undefined, undefined, Req, State) ->
    Segs = cb_segmentation:list_segments(),
    reply(200, #{segments => [segment_to_map(S) || S <- Segs]}, Req, State);

handle(<<"POST">>, <<"segments">>, undefined, undefined, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{name := N, description := D, rule := R}, _} ->
            {ok, Id} = cb_segmentation:define_segment(N, D, R),
            reply(201, #{segment_id => Id}, Req2, State);
        _ ->
            error_reply(400, <<"Missing required fields">>, Req2, State)
    end;

handle(<<"GET">>, <<"segments">>, Id, undefined, Req, State) ->
    case cb_segmentation:get_segment(Id) of
        {ok, S}            -> reply(200, segment_to_map(S), Req, State);
        {error, not_found} -> error_reply(404, <<"Segment not found">>, Req, State)
    end;

handle(<<"POST">>, <<"segments">>, Id, <<"retire">>, Req, State) ->
    case cb_segmentation:retire_segment(Id) of
        ok                 -> reply(200, #{status => retired}, Req, State);
        {error, not_found} -> error_reply(404, <<"Segment not found">>, Req, State)
    end;

handle(<<"POST">>, <<"segments">>, Id, <<"assign">>, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{party_id := P}, _} ->
            case cb_segmentation:assign(Id, P) of
                {ok, MId}       -> reply(201, #{membership_id => MId}, Req2, State);
                {error, Reason} -> error_reply(400, Reason, Req2, State)
            end;
        _ ->
            error_reply(400, <<"Missing party_id">>, Req2, State)
    end;

handle(<<"GET">>, <<"recommendations">>, undefined, undefined, Req, State) ->
    Recs = cb_recommendations:list_pending(),
    reply(200, #{recommendations => [rec_to_map(R) || R <- Recs]}, Req, State);

handle(<<"POST">>, <<"recommendations">>, undefined, undefined, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{party_id := P, product_code := PC, score := S, rationale := R}, _}
                when is_float(S); is_integer(S) ->
            FS = to_float(S),
            case cb_recommendations:create(P, PC, FS, R) of
                {ok, Id}        -> reply(201, #{recommendation_id => Id}, Req2, State);
                {error, Reason} -> error_reply(400, Reason, Req2, State)
            end;
        _ ->
            error_reply(400, <<"Missing required fields">>, Req2, State)
    end;

handle(<<"GET">>, <<"recommendations">>, Id, undefined, Req, State) ->
    case cb_recommendations:get(Id) of
        {ok, R}            -> reply(200, rec_to_map(R), Req, State);
        {error, not_found} -> error_reply(404, <<"Recommendation not found">>,
                                          Req, State)
    end;

handle(<<"POST">>, <<"recommendations">>, Id, Action, Req, State)
        when Action =:= <<"deliver">>;
             Action =:= <<"accept">>;
             Action =:= <<"dismiss">> ->
    NewStatus = case Action of
        <<"deliver">> -> delivered;
        <<"accept">>  -> accepted;
        <<"dismiss">> -> dismissed
    end,
    case cb_recommendations:transition(Id, NewStatus) of
        ok                              -> reply(200, #{status => NewStatus},
                                                 Req, State);
        {error, not_found}              -> error_reply(404,
                                            <<"Recommendation not found">>,
                                            Req, State);
        {error, invalid_transition}     -> error_reply(409,
                                            <<"Invalid transition">>,
                                            Req, State)
    end;

handle(_, _, _, _, Req, State) ->
    error_reply(405, <<"Method not allowed">>, Req, State).

to_float(N) when is_integer(N) -> N * 1.0;
to_float(F) when is_float(F)   -> F.

segment_to_map(S) ->
    #{segment_id  => S#customer_segment.segment_id,
      name        => S#customer_segment.name,
      description => S#customer_segment.description,
      rule        => S#customer_segment.rule,
      status      => S#customer_segment.status,
      created_at  => S#customer_segment.created_at,
      updated_at  => S#customer_segment.updated_at}.

rec_to_map(R) ->
    #{recommendation_id => R#product_recommendation.recommendation_id,
      party_id          => R#product_recommendation.party_id,
      product_code      => R#product_recommendation.product_code,
      score             => R#product_recommendation.score,
      rationale         => R#product_recommendation.rationale,
      status            => R#product_recommendation.status,
      created_at        => R#product_recommendation.created_at,
      updated_at        => R#product_recommendation.updated_at}.

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
