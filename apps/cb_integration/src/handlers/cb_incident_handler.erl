%% @doc Operations incident response automation handler.
-module(cb_incident_handler).

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    Path = cowboy_req:path(Req),
    handle(Method, Path, Req, State).

handle(<<"GET">>, <<"/api/v1/operations/incidents">>, Req, State) ->
    case query_filters(Req) of
        {ok, Filters} ->
            case maybe_sync(Filters) of
                ok ->
                    case cb_incident_automation:list_incidents(Filters) of
                        {ok, Result} -> json_reply(200, Result, Req, State);
                        {error, Reason} -> reply_error(Reason, Req, State)
                    end;
                {error, Reason} ->
                    reply_error(Reason, Req, State)
            end;
        {error, Reason} ->
            reply_error(Reason, Req, State)
    end;
handle(<<"POST">>, <<"/api/v1/operations/incidents/sync">>, Req, State) ->
    case cb_incident_automation:sync_from_slo() of
        {ok, Result} -> json_reply(200, Result, Req, State);
        {error, Reason} -> reply_error(Reason, Req, State)
    end;
handle(<<"GET">>, <<"/api/v1/operations/incidents/templates">>, Req, State) ->
    json_reply(200, #{items => cb_incident_automation:templates()}, Req, State);
handle(<<"POST">>, Path, Req, State) ->
    handle_post_action(Path, Req, State);
handle(<<"OPTIONS">>, _Path, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};
handle(_, _Path, Req, State) ->
    reply_error(method_not_allowed, Req, State).

handle_post_action(<<"/api/v1/operations/incidents/", _/binary>> = Path, Req, State) ->
    IncidentId = cowboy_req:binding(incident_id, Req),
    Action = cowboy_req:binding(action, Req),
    {ok, Body, Req1} = cowboy_req:read_body(Req),
    case decode_body(Body) of
        {ok, Params} ->
            case {Path, Action} of
                {_, <<"ack">>} ->
                    Owner = normalize_text(maps:get(<<"owner">>, Params, actor_email())),
                    case cb_incident_automation:acknowledge(IncidentId, Owner) of
                        {ok, Result} -> json_reply(200, Result, Req1, State);
                        {error, Reason} -> reply_error(Reason, Req1, State)
                    end;
                {_, <<"resolve">>} ->
                    Resolver = normalize_text(maps:get(<<"resolved_by">>, Params, actor_email())),
                    Summary = normalize_text(maps:get(<<"summary">>, Params,
                        <<"Resolved after operational mitigation and verification">>)),
                    case cb_incident_automation:resolve(IncidentId, Resolver, Summary) of
                        {ok, Result} -> json_reply(200, Result, Req1, State);
                        {error, Reason} -> reply_error(Reason, Req1, State)
                    end;
                _ ->
                    reply_error(method_not_allowed, Req1, State)
            end;
        {error, Reason} ->
            reply_error(Reason, Req1, State)
    end;
handle_post_action(_Path, Req, State) ->
    reply_error(method_not_allowed, Req, State).

maybe_sync(Filters) ->
    case maps:get(sync, Filters, false) of
        true ->
            case cb_incident_automation:sync_from_slo() of
                {ok, _} -> ok;
                {error, Reason} -> {error, Reason}
            end;
        false ->
            ok
    end.

query_filters(Req) ->
    Qs = cowboy_req:parse_qs(Req),
    case parse_integer_filters(Qs) of
        {ok, IntFilters} ->
            {ok, IntFilters#{
                status => proplists:get_value(<<"status">>, Qs, undefined),
                severity => proplists:get_value(<<"severity">>, Qs, undefined),
                objective => proplists:get_value(<<"objective">>, Qs, undefined),
                sync => bool_param(<<"sync">>, Qs)
            }};
        Error ->
            Error
    end.

parse_integer_filters(Qs) ->
    with_integer_params([
        {limit, <<"limit">>, 50},
        {offset, <<"offset">>, 0}
    ], Qs, #{}).

with_integer_params([], _Qs, Acc) ->
    {ok, Acc};
with_integer_params([{Key, QsKey, Default} | Rest], Qs, Acc) ->
    case cb_validate:integer_param(QsKey, Qs, Default) of
        {ok, Value} -> with_integer_params(Rest, Qs, Acc#{Key => Value});
        {error, _} -> {error, invalid_parameters}
    end.

bool_param(Key, Qs) ->
    case proplists:get_value(Key, Qs, <<"false">>) of
        <<"1">> -> true;
        <<"true">> -> true;
        <<"TRUE">> -> true;
        _ -> false
    end.

decode_body(<<>>) ->
    {ok, #{}};
decode_body(Body) ->
    case jsone:try_decode(Body) of
        {ok, Decoded, _} when is_map(Decoded) -> {ok, Decoded};
        _ -> {error, invalid_json}
    end.

actor_email() ->
    case erlang:get(auth_user) of
        #{email := Email} when is_binary(Email) -> Email;
        _ -> <<"operations@system">>
    end.

normalize_text(Value) when is_binary(Value) ->
    Value;
normalize_text(Value) when is_atom(Value) ->
    atom_to_binary(Value, utf8);
normalize_text(Value) when is_integer(Value) ->
    integer_to_binary(Value);
normalize_text(Value) ->
    iolist_to_binary(io_lib:format("~p", [Value])).

reply_error(Reason, Req, State) ->
    {Status, ErrorAtom, Message} = cb_http_errors:to_response(normalize_reason(Reason)),
    json_reply(Status, #{error => ErrorAtom, message => Message}, Req, State).

normalize_reason(invalid_parameters) -> invalid_parameters;
normalize_reason(invalid_json) -> invalid_json;
normalize_reason(not_found) -> not_found;
normalize_reason(already_resolved) -> invalid_alert_status;
normalize_reason(method_not_allowed) -> method_not_allowed;
normalize_reason(Reason) when is_atom(Reason) -> Reason;
normalize_reason(_) -> internal_error.

json_reply(Status, Body, Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Body), Req),
    {ok, Req2, State}.
