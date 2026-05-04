%% @doc HTTP handler for feature store and pipelines (TASK-074).
%%
%% Routes:
%%   GET  /api/v1/analytics/features
%%   POST /api/v1/analytics/features
%%   GET  /api/v1/analytics/features/:key
%%   POST /api/v1/analytics/features/:key/values
%%   GET  /api/v1/analytics/features/:key/values/latest?entity_id=...
%%   GET  /api/v1/analytics/pipelines
%%   POST /api/v1/analytics/pipelines
%%   POST /api/v1/analytics/pipelines/:id/:action  (activate|retire)
-module(cb_feature_store_handler).
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

handle(<<"GET">>, <<"features">>, undefined, undefined, Req, State) ->
    Defs = cb_feature_store:list_features(),
    reply(200, #{features => [feature_to_map(D) || D <- Defs]}, Req, State);

handle(<<"POST">>, <<"features">>, undefined, undefined, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{feature_key := K, pipeline_id := P, description := D,
               value_type := VT, owner := O}, _} ->
            case cb_feature_store:register_feature(K, P, D, atomize_vt(VT), O) of
                {ok, Id}        -> reply(201, #{feature_id => Id}, Req2, State);
                {error, Reason} -> error_reply(400, Reason, Req2, State)
            end;
        _ ->
            error_reply(400, <<"Missing required fields">>, Req2, State)
    end;

handle(<<"GET">>, <<"features">>, Key, undefined, Req, State) ->
    case cb_feature_store:get_feature(Key) of
        {ok, F}            -> reply(200, feature_to_map(F), Req, State);
        {error, not_found} -> error_reply(404, <<"Feature not found">>, Req, State)
    end;

handle(<<"POST">>, <<"features">>, Key, <<"values">>, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{entity_id := E, value := V}, _} ->
            case cb_feature_store:write_value(Key, E, V) of
                {ok, Id}        -> reply(201, #{value_id => Id}, Req2, State);
                {error, Reason} -> error_reply(400, Reason, Req2, State)
            end;
        _ ->
            error_reply(400, <<"Missing required fields: entity_id, value">>,
                        Req2, State)
    end;

handle(<<"GET">>, <<"pipelines">>, undefined, undefined, Req, State) ->
    Ps = cb_feature_store:list_pipelines(),
    reply(200, #{pipelines => [pipeline_to_map(P) || P <- Ps]}, Req, State);

handle(<<"POST">>, <<"pipelines">>, undefined, undefined, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{name := N, description := D, schedule_ms := S}, _}
                when is_integer(S), S > 0 ->
            {ok, Id} = cb_feature_store:register_pipeline(N, D, S),
            reply(201, #{pipeline_id => Id}, Req2, State);
        _ ->
            error_reply(400, <<"Missing required fields">>, Req2, State)
    end;

handle(<<"POST">>, <<"pipelines">>, PipelineId, Action, Req, State)
        when Action =:= <<"activate">>; Action =:= <<"retire">> ->
    Status = case Action of
        <<"activate">> -> active;
        <<"retire">>   -> retired
    end,
    case cb_feature_store:set_pipeline_status(PipelineId, Status) of
        ok                 -> reply(200, #{status => Status}, Req, State);
        {error, not_found} -> error_reply(404, <<"Pipeline not found">>, Req, State)
    end;

handle(_, _, _, _, Req, State) ->
    error_reply(405, <<"Method not allowed">>, Req, State).

atomize_vt(<<"numeric">>)     -> numeric;
atomize_vt(<<"categorical">>) -> categorical;
atomize_vt(<<"boolean">>)     -> boolean;
atomize_vt(<<"timestamp">>)   -> timestamp;
atomize_vt(numeric)           -> numeric;
atomize_vt(categorical)       -> categorical;
atomize_vt(boolean)           -> boolean;
atomize_vt(timestamp)         -> timestamp;
atomize_vt(_)                 -> numeric.

feature_to_map(F) ->
    #{feature_id  => F#feature_definition.feature_id,
      feature_key => F#feature_definition.feature_key,
      pipeline_id => F#feature_definition.pipeline_id,
      description => F#feature_definition.description,
      value_type  => F#feature_definition.value_type,
      owner       => F#feature_definition.owner,
      created_at  => F#feature_definition.created_at,
      updated_at  => F#feature_definition.updated_at}.

pipeline_to_map(P) ->
    #{pipeline_id => P#feature_pipeline.pipeline_id,
      name        => P#feature_pipeline.name,
      description => P#feature_pipeline.description,
      schedule_ms => P#feature_pipeline.schedule_ms,
      status      => P#feature_pipeline.status,
      last_run_at => P#feature_pipeline.last_run_at,
      created_at  => P#feature_pipeline.created_at}.

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
