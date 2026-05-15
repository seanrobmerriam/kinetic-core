%% @doc Audit Retention Handler
%%
%% Handler for audit retention policy management.
%%
%% <h2>REST API Endpoints</h2>
%%
%% <ul>
%%   <li><b>POST /api/v1/audit/retention-policies</b> — Set retention policy for a resource</li>
%%   <li><b>GET /api/v1/audit/retention-policies</b> — List all retention policies</li>
%%   <li><b>POST /api/v1/audit/apply-retention</b> — Trigger retention enforcement</li>
%%   <li><b>OPTIONS</b> — CORS preflight</li>
%% </ul>
%%
-module(cb_audit_retention_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    handle(Method, Req, State).

%% POST /api/v1/audit/retention-policies — set policy
handle(<<"POST">>, Req, State) ->
    case cowboy_req:path(Req) of
        <<"/api/v1/audit/apply-retention">> ->
            case cb_audit_retention:apply_retention_policies() of
                {ok, Results} ->
                    Resp = #{
                        message => <<"Retention policies applied successfully">>,
                        results => Results
                    },
                    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                    Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req),
                    {ok, Req2, State};
                {error, Reason} ->
                    {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
                    Resp = #{error => ErrorAtom, message => Message},
                    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
                    {ok, Req2, State}
            end;
        <<"/api/v1/audit/retention-policies">> ->
            {ok, BodyBin, Req1} = cowboy_req:read_body(Req),
            case jsone:try_decode(BodyBin) of
                {ok, Body, _} ->
                    Resource = binary_to_atom(maps:get(<<"resource">>, Body), utf8),
                    RetentionDays = maps:get(<<"retention_days">>, Body),
                    case cb_audit_retention:set_retention_policy(Resource, RetentionDays) of
                        ok ->
                            Resp = #{
                                resource => Resource,
                                retention_days => RetentionDays,
                                message => <<"Retention policy set successfully">>
                            },
                            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                            Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req1),
                            {ok, Req2, State};
                        {error, Reason} ->
                            {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
                            Resp = #{error => ErrorAtom, message => Message},
                            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                            Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req1),
                            {ok, Req2, State}
                    end;
                _ ->
                    {Code, Hdrs, Body} = cb_http_errors:to_response_with_metrics(invalid_json),
                    Req2 = cowboy_req:reply(Code, Hdrs, Body, Req1),
                    {ok, Req2, State}
            end;
        _ ->
            {Code405, Hdrs405, Body405} = cb_http_errors:to_response_with_metrics(method_not_allowed),
            Req2 = cowboy_req:reply(Code405, Hdrs405, Body405, Req),
            {ok, Req2, State}
    end;

%% GET /api/v1/audit/retention-policies — list all policies
handle(<<"GET">>, Req, State) ->
    F = fun() -> mnesia:all_keys(audit_retention_policy) end,
    case mnesia:transaction(F) of
        {atomic, Keys} ->
            Policies = lists:map(fun(K) -> get_policy_json(K) end, Keys),
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(200, Headers, jsone:encode(Policies), Req),
            {ok, Req2, State};
        {aborted, _} ->
            {Code, Hdrs, Body} = cb_http_errors:to_response_with_metrics(internal_error),
            Req2 = cowboy_req:reply(Code, Hdrs, Body, Req),
            {ok, Req2, State}
    end;

handle(<<"OPTIONS">>, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, Req, State) ->
    {Code405, Hdrs405, Body405} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(Code405, Hdrs405, Body405, Req),
    {ok, Req2, State}.

get_policy_json(Resource) ->
    {ok, Days} = cb_audit_retention:get_retention_policy(Resource),
    #{
        resource => Resource,
        retention_days => Days
    }.