%% @doc Operations handler for schema migration status, apply, and rollback.
-module(cb_schema_migrations_handler).

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    Path = cowboy_req:path(Req),
    handle(Method, Path, Req, State).

handle(<<"GET">>, <<"/api/v1/operations/schema-migrations">>, Req, State) ->
    json_reply(200, cb_schema_migrations:status(), Req, State);
handle(<<"GET">>, <<"/api/v1/operations/schema-migrations/compat">>, Req, State) ->
    Result = case cb_schema_compat:check() of
        ok ->
            #{status => <<"ok">>, violations => []};
        {violations, Violations} ->
            #{status => <<"violations">>, violations => violations_to_json(Violations)}
    end,
    json_reply(200, Result, Req, State);
handle(<<"POST">>, <<"/api/v1/operations/schema-migrations/apply">>, Req, State) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req),
    case decode_body(Body) of
        {ok, Params} ->
            case target_from_body(Params, cb_schema_migrations:target_version()) of
                {ok, Target} ->
                    case cb_schema_migrations:migrate_to(Target) of
                        {ok, Result} -> json_reply(200, Result, Req1, State);
                        {error, Reason} -> reply_error(Reason, Req1, State)
                    end;
                {error, Reason} ->
                    reply_error(Reason, Req1, State)
            end;
        {error, Reason} ->
            reply_error(Reason, Req1, State)
    end;
handle(<<"POST">>, <<"/api/v1/operations/schema-migrations/rollback">>, Req, State) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req),
    case decode_body(Body) of
        {ok, Params} ->
            case target_from_body(Params, undefined) of
                {ok, Target} ->
                    case cb_schema_migrations:rollback_to(Target) of
                        {ok, Result} -> json_reply(200, Result, Req1, State);
                        {error, Reason} -> reply_error(Reason, Req1, State)
                    end;
                {error, Reason} ->
                    reply_error(Reason, Req1, State)
            end;
        {error, Reason} ->
            reply_error(Reason, Req1, State)
    end;
handle(<<"OPTIONS">>, _Path, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};
handle(_, _Path, Req, State) ->
    reply_error(method_not_allowed, Req, State).

decode_body(<<>>) ->
    {ok, #{}};
decode_body(Body) ->
    case jsone:try_decode(Body) of
        {ok, Map, _} when is_map(Map) -> {ok, Map};
        _ -> {error, invalid_json}
    end.

target_from_body(Body, Default) ->
    case maps:find(<<"target_version">>, Body) of
        {ok, Value} ->
            normalize_target(Value);
        error when is_integer(Default), Default >= 0 ->
            {ok, Default};
        error ->
            {error, missing_required_field}
    end.

normalize_target(Value) when is_integer(Value), Value >= 0 ->
    {ok, Value};
normalize_target(_) ->
    {error, invalid_parameters}.

reply_error(Reason, Req, State) ->
    case normalize_reason(Reason) of
        {Status, Error, Message} ->
            json_reply(Status, #{error => Error, message => Message}, Req, State)
    end.

normalize_reason(target_below_current) ->
    {409, <<"target_below_current">>, <<"Target version is below current schema version">>};
normalize_reason(target_above_current) ->
    {409, <<"target_above_current">>, <<"Rollback target exceeds current schema version">>};
normalize_reason(unsupported_target_version) ->
    {422, <<"unsupported_target_version">>, <<"Target schema version is not supported">>};
normalize_reason({backward_compat_violations, Violations}) ->
    Msg = iolist_to_binary([
        <<"Schema backward-compat violations detected: ">>,
        iolist_to_binary(lists:join(<<", ">>, [violation_summary(V) || V <- Violations]))
    ]),
    {409, <<"backward_compat_violations">>, Msg};
normalize_reason(invalid_json) ->
    cb_http_errors:to_response(invalid_json);
normalize_reason(invalid_parameters) ->
    cb_http_errors:to_response(invalid_parameters);
normalize_reason(missing_required_field) ->
    cb_http_errors:to_response(missing_required_field);
normalize_reason(method_not_allowed) ->
    cb_http_errors:to_response(method_not_allowed);
normalize_reason(Reason) when is_atom(Reason) ->
    cb_http_errors:to_response(Reason);
normalize_reason(_) ->
    cb_http_errors:to_response(internal_error).

violations_to_json(Violations) ->
    lists:map(fun violation_to_map/1, Violations).

violation_to_map({Table, table_missing}) ->
    #{table => atom_to_binary(Table, utf8), kind => <<"table_missing">>, removed_fields => []};
violation_to_map({Table, removed_fields, Fields}) ->
    #{table => atom_to_binary(Table, utf8),
      kind => <<"removed_fields">>,
      removed_fields => [atom_to_binary(F, utf8) || F <- Fields]}.

violation_summary({Table, table_missing}) ->
    [atom_to_binary(Table, utf8), <<" missing">>];
violation_summary({Table, removed_fields, Fields}) ->
    [atom_to_binary(Table, utf8), <<"(">>,
     iolist_to_binary(lists:join(<<",">>, [atom_to_binary(F, utf8) || F <- Fields])),
     <<")">>].

json_reply(Status, Body, Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Body), Req),
    {ok, Req2, State}.