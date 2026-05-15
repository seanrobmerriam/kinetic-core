%% @doc Contract experiment endpoints for variant assignment.
%%
%% Routes:
%%   GET  /api/v1/contracts/:contract_id/experiments
%%   POST /api/v1/contracts/:contract_id/experiments
%%   GET  /api/v1/contracts/:contract_id/experiments/:experiment_id
%%   POST /api/v1/contracts/:contract_id/experiments/:experiment_id/activate
%%   POST /api/v1/contracts/:contract_id/experiments/:experiment_id/stop
%%   POST /api/v1/contracts/:contract_id/experiments/:experiment_id/assign
-module(cb_contract_experiments_handler).

-include_lib("cb_contracts/include/cb_contracts.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    ContractId = cowboy_req:binding(contract_id, Req, undefined),
    ExperimentId = cowboy_req:binding(experiment_id, Req, undefined),
    Action = cowboy_req:binding(action, Req, undefined),
    handle(Method, ContractId, ExperimentId, Action, Req, State).

handle(<<"GET">>, ContractId, undefined, undefined, Req, State) ->
    Items = cb_contracts:list_experiments(ContractId),
    json_reply(200, #{items => [experiment_to_map(I) || I <- Items], total => length(Items)}, Req, State);

handle(<<"POST">>, ContractId, undefined, undefined, Req, State) ->
    {ok, BodyBin, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(BodyBin) of
        {ok, Json, _} when is_map(Json) ->
            Name = maps:get(<<"name">>, Json, undefined),
            Variants = normalize_variants(maps:get(<<"variants">>, Json, [])),
            CreatedBy = maps:get(<<"created_by">>, Json, undefined),
            case cb_contracts:create_experiment(ContractId, Name, Variants, CreatedBy) of
                {ok, Exp} -> json_reply(201, experiment_to_map(Exp), Req2, State);
                {error, Reason} -> reply_error(Reason, Req2, State)
            end;
        _ ->
            reply_error(invalid_json, Req2, State)
    end;

handle(<<"GET">>, ContractId, ExperimentId, undefined, Req, State) ->
    case cb_contracts:get_experiment(ContractId, ExperimentId) of
        {ok, Exp} -> json_reply(200, experiment_to_map(Exp), Req, State);
        {error, Reason} -> reply_error(Reason, Req, State)
    end;

handle(<<"POST">>, ContractId, ExperimentId, <<"activate">>, Req, State) ->
    case cb_contracts:activate_experiment(ContractId, ExperimentId) of
        {ok, Exp} -> json_reply(200, experiment_to_map(Exp), Req, State);
        {error, Reason} -> reply_error(Reason, Req, State)
    end;

handle(<<"POST">>, ContractId, ExperimentId, <<"stop">>, Req, State) ->
    case cb_contracts:stop_experiment(ContractId, ExperimentId) of
        {ok, Exp} -> json_reply(200, experiment_to_map(Exp), Req, State);
        {error, Reason} -> reply_error(Reason, Req, State)
    end;

handle(<<"POST">>, ContractId, ExperimentId, <<"assign">>, Req, State) ->
    {ok, BodyBin, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(BodyBin) of
        {ok, Json, _} when is_map(Json) ->
            SubjectKey = maps:get(<<"subject_key">>, Json, undefined),
            case cb_contracts:assign_variant(ContractId, ExperimentId, SubjectKey) of
                {ok, Version, Variant} ->
                    json_reply(200, #{contract_id => ContractId,
                                      experiment_id => ExperimentId,
                                      assigned_version => Version,
                                      variant => Variant}, Req2, State);
                {error, Reason} ->
                    reply_error(Reason, Req2, State)
            end;
        _ ->
            reply_error(invalid_json, Req2, State)
    end;

handle(<<"OPTIONS">>, _ContractId, _ExperimentId, _Action, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _ContractId, _ExperimentId, _Action, Req, State) ->
    {Code, Hdrs, RespBody} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(Code, Hdrs, RespBody, Req),
    {ok, Req2, State}.

normalize_variants([]) -> [];
normalize_variants([Item | Rest]) when is_map(Item) ->
    Version = maps:get(<<"version">>, Item, undefined),
    Weight = maps:get(<<"weight">>, Item, undefined),
    [#{version => Version, weight => Weight} | normalize_variants(Rest)];
normalize_variants(_Other) ->
    [].

reply_error(Reason, Req, State) ->
    {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
    json_reply(Status, #{error => ErrorAtom, message => Message}, Req, State).

json_reply(Status, Body, Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Body), Req),
    {ok, Req2, State}.

experiment_to_map(#contract_experiment{
    experiment_id = ExperimentId,
    contract_id = ContractId,
    name = Name,
    status = Status,
    variants = Variants,
    allocation_seed = Seed,
    created_by = CreatedBy,
    created_at = CreatedAt,
    updated_at = UpdatedAt
}) ->
    #{experiment_id => ExperimentId,
      contract_id => ContractId,
      name => Name,
      status => Status,
      variants => Variants,
      allocation_seed => Seed,
      created_by => CreatedBy,
      created_at => CreatedAt,
      updated_at => UpdatedAt}.
