%% @doc Regulatory evidence export handler (TASK-095).
%%
%% Routes:
%%   POST /api/v1/audit/evidence/:resource
%%   GET  /api/v1/audit/evidence/exports
%%   GET  /api/v1/audit/evidence/exports/:export_id
%%   POST /api/v1/audit/evidence/exports/:export_id/verify
-module(cb_regulatory_evidence_handler).

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    Path = cowboy_req:path(Req),
    Resource = cowboy_req:binding(resource, Req, undefined),
    ExportId = cowboy_req:binding(export_id, Req, undefined),
    Action = cowboy_req:binding(action, Req, undefined),
    handle(Method, Path, Resource, ExportId, Action, Req, State).

handle(<<"GET">>, <<"/api/v1/audit/evidence/exports">>, _Resource, _ExportId, _Action, Req, State) ->
    case cb_regulatory_evidence:list_exports() of
        {ok, Items} ->
            json_reply(200, #{items => Items, total => length(Items)}, Req, State);
        {error, Reason} ->
            reply_error(Reason, Req, State)
    end;

handle(<<"GET">>, _Path, _Resource, ExportId, undefined, Req, State)
        when ExportId =/= undefined ->
    case cb_regulatory_evidence:get_export(ExportId) of
        {ok, Export} ->
            json_reply(200, Export, Req, State);
        {error, Reason} ->
            reply_error(Reason, Req, State)
    end;

handle(<<"POST">>, _Path, _Resource, ExportId, <<"verify">>, Req, State)
        when ExportId =/= undefined ->
    case cb_regulatory_evidence:verify_export(ExportId) of
        {ok, Result} ->
            json_reply(200, Result, Req, State);
        {error, Reason} ->
            reply_error(Reason, Req, State)
    end;

handle(<<"POST">>, _Path, Resource, _ExportId, _Action, Req, State)
        when Resource =/= undefined ->
    {ok, Body, Req1} = cowboy_req:read_body(Req),
    case decode_request_body(Body) of
        {ok, Decoded} ->
            Filters = maps:get(<<"filters">>, Decoded, #{}),
            RequestedBy0 = maps:get(<<"requested_by">>, Decoded, undefined),
            RequestedBy = caller_id(RequestedBy0),
            case cb_regulatory_evidence:generate(Resource, Filters, RequestedBy) of
                {ok, Bundle} ->
                    json_reply(201, Bundle, Req1, State);
                {error, unsupported_resource} ->
                    reply_error(not_found, Req1, State);
                {error, Reason} ->
                    reply_error(Reason, Req1, State)
            end;
        {error, invalid_json} ->
            reply_error(invalid_json, Req1, State)
    end;

handle(<<"OPTIONS">>, _Path, _Resource, _ExportId, _Action, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _Path, _Resource, _ExportId, _Action, Req, State) ->
    reply_error(method_not_allowed, Req, State).

%% =============================================================================
%% Internal Helpers
%% =============================================================================

decode_request_body(<<>>) ->
    {ok, #{}};
decode_request_body(Body) when is_binary(Body) ->
    case jsone:try_decode(Body) of
        {ok, Decoded, _} when is_map(Decoded) -> {ok, Decoded};
        _ -> {error, invalid_json}
    end.

caller_id(undefined) ->
    Session = erlang:get(auth_session),
    case Session of
        S when is_map(S) ->
            maps:get(user_id, S, <<"unknown">>);
        _ ->
            <<"unknown">>
    end;
caller_id(Value) when is_binary(Value) ->
    Value.

reply_error(Reason, Req, State) ->
    {Status, ErrorAtom, Message} = cb_http_errors:to_response(normalize_reason(Reason)),
    json_reply(Status, #{error => ErrorAtom, message => Message}, Req, State).

normalize_reason(not_found) -> not_found;
normalize_reason(database_error) -> database_error;
normalize_reason(invalid_export_payload) -> invalid_parameters;
normalize_reason({unsupported_format, _, _}) -> invalid_parameters;
normalize_reason(Reason) when is_atom(Reason) -> Reason;
normalize_reason(_) -> internal_error.

json_reply(Status, Body, Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Body), Req),
    {ok, Req2, State}.
