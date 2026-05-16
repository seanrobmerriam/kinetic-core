%% @doc Operations handler for structured log search, retention, and export.
-module(cb_structured_logs_handler).

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    Path = cowboy_req:path(Req),
    handle(Method, Path, Req, State).

handle(<<"GET">>, <<"/api/v1/operations/logs">>, Req, State) ->
    case query_filters(Req) of
        {ok, Filters} ->
            case cb_structured_logs:search(Filters) of
                {ok, Result} -> json_reply(200, Result, Req, State);
                {error, Reason} -> reply_error(Reason, Req, State)
            end;
        {error, Reason} ->
            reply_error(Reason, Req, State)
    end;
handle(<<"GET">>, <<"/api/v1/operations/logs/export">>, Req, State) ->
    case query_filters(Req) of
        {ok, Filters} ->
            case cb_structured_logs:export_csv(Filters) of
                {ok, Csv} ->
                    Headers = maps:merge(
                        #{
                            <<"content-type">> => <<"text/csv">>,
                            <<"content-disposition">> => <<"attachment; filename=\"structured-logs.csv\"">>
                        },
                        cb_cors:headers()
                    ),
                    Req2 = cowboy_req:reply(200, Headers, Csv, Req),
                    {ok, Req2, State};
                {error, Reason} ->
                    reply_error(Reason, Req, State)
            end;
        {error, Reason} ->
            reply_error(Reason, Req, State)
    end;
handle(<<"GET">>, <<"/api/v1/operations/logs/retention">>, Req, State) ->
    case cb_structured_logs:get_retention_policy() of
        {ok, Policy} -> json_reply(200, Policy, Req, State);
        {error, Reason} -> reply_error(Reason, Req, State)
    end;
handle(<<"POST">>, <<"/api/v1/operations/logs/retention">>, Req, State) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req),
    case decode_body(Body) of
        {ok, Params} ->
            case maps:get(<<"retention_days">>, Params, invalid) of
                Days when is_integer(Days), Days >= 0 ->
                    case cb_structured_logs:set_retention_policy(Days) of
                        ok ->
                            json_reply(200, #{resource => <<"structured_log">>, retention_days => Days}, Req1, State);
                        {error, Reason} ->
                            reply_error(Reason, Req1, State)
                    end;
                _ ->
                    reply_error(invalid_parameters, Req1, State)
            end;
        {error, Reason} ->
            reply_error(Reason, Req1, State)
    end;
handle(<<"POST">>, <<"/api/v1/operations/logs/retention/apply">>, Req, State) ->
    case cb_structured_logs:apply_retention() of
        {ok, Result} -> json_reply(200, Result, Req, State);
        {error, Reason} -> reply_error(Reason, Req, State)
    end;
handle(<<"OPTIONS">>, _Path, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};
handle(_, _Path, Req, State) ->
    reply_error(method_not_allowed, Req, State).

query_filters(Req) ->
    Qs = cowboy_req:parse_qs(Req),
    case parse_integer_filters(Qs) of
        {ok, IntFilters} ->
            {ok, IntFilters# {
                correlation_id => proplists:get_value(<<"correlation_id">>, Qs, undefined),
                event => proplists:get_value(<<"event">>, Qs, undefined),
                level => proplists:get_value(<<"level">>, Qs, undefined),
                method => proplists:get_value(<<"method">>, Qs, undefined),
                path => proplists:get_value(<<"path">>, Qs, undefined),
                q => proplists:get_value(<<"q">>, Qs, undefined)
            }};
        Error ->
            Error
    end.

parse_integer_filters(Qs) ->
    with_integer_params([
        {from, <<"from">>, undefined},
        {to, <<"to">>, undefined},
        {limit, <<"limit">>, 100},
        {offset, <<"offset">>, 0}
    ], Qs, #{}).

with_integer_params([], _Qs, Acc) ->
    {ok, Acc};
with_integer_params([{Key, QsKey, Default} | Rest], Qs, Acc) ->
    case integer_param(QsKey, Qs, Default) of
        {ok, undefined} -> with_integer_params(Rest, Qs, Acc);
        {ok, Value} -> with_integer_params(Rest, Qs, Acc#{Key => Value});
        {error, _} -> {error, invalid_parameters}
    end.

integer_param(_Key, Qs, undefined) ->
    case proplists:get_value(_Key, Qs, undefined) of
        undefined -> {ok, undefined};
        Value when is_binary(Value) ->
            try {ok, binary_to_integer(Value)}
            catch _:_ -> {error, invalid_parameters}
            end
    end;
integer_param(Key, Qs, Default) ->
    cb_validate:integer_param(Key, Qs, Default).

decode_body(<<>>) ->
    {ok, #{}};
decode_body(Body) ->
    case jsone:try_decode(Body) of
        {ok, Decoded, _} when is_map(Decoded) -> {ok, Decoded};
        _ -> {error, invalid_json}
    end.

reply_error(Reason, Req, State) ->
    {Status, ErrorAtom, Message} = cb_http_errors:to_response(normalize_reason(Reason)),
    json_reply(Status, #{error => ErrorAtom, message => Message}, Req, State).

normalize_reason(invalid_parameters) -> invalid_parameters;
normalize_reason(invalid_json) -> invalid_json;
normalize_reason(Reason) when is_atom(Reason) -> Reason;
normalize_reason(_) -> internal_error.

json_reply(Status, Body, Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Body), Req),
    {ok, Req2, State}.