%% @doc HTTP handler for Risk and Capital API (TASK-064)
%%
%% Routes:
%%   POST   /api/v1/risk/metrics              — record_metric
%%   GET    /api/v1/risk/metrics              — list_metrics (query: account_id, metric_type)
%%   GET    /api/v1/risk/metrics/:id          — get_metric
%%   GET    /api/v1/risk/breaches             — current_breaches
%%   POST   /api/v1/risk/check               — check_limit (inline, no persistence)
%%   POST   /api/v1/capital/buffers          — allocate_buffer
%%   GET    /api/v1/capital/buffers          — list_buffers
%%   GET    /api/v1/capital/buffers/:id      — get_buffer
%%   DELETE /api/v1/capital/buffers/:id      — release_buffer
-module(cb_risk_capital_handler).

-include("../../cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

init(Req0, State) ->
    Method   = cowboy_req:method(Req0),
    PathInfo = cowboy_req:path_info(Req0),
    Path     = cowboy_req:path(Req0),
    {ok, Req} = dispatch(Method, Path, PathInfo, Req0),
    {ok, Req, State}.

dispatch(<<"POST">>,   P, [],   Req0) -> post_route(P, Req0);
dispatch(<<"GET">>,    P, [],   Req0) -> get_route(P, Req0);
dispatch(<<"GET">>,    P, [Id], Req0) -> get_id_route(P, Id, Req0);
dispatch(<<"DELETE">>, P, [Id], Req0) -> delete_route(P, Id, Req0);
dispatch(_,            _, _,    Req0) -> cb_http_util:reply_error(405, <<"method_not_allowed">>, Req0).

post_route(P, Req0) ->
    case binary:match(P, <<"/capital/buffers">>) of
        {_, _} -> handle_allocate_buffer(Req0);
        nomatch ->
            case binary:match(P, <<"/risk/check">>) of
                {_, _} -> handle_check_limit(Req0);
                nomatch -> handle_record_metric(Req0)
            end
    end.

get_route(P, Req0) ->
    case binary:match(P, <<"/capital/buffers">>) of
        {_, _} -> handle_list_buffers(Req0);
        nomatch ->
            case binary:match(P, <<"/breaches">>) of
                {_, _} -> handle_current_breaches(Req0);
                nomatch -> handle_list_metrics(Req0)
            end
    end.

get_id_route(P, Id, Req0) ->
    case binary:match(P, <<"/capital/buffers">>) of
        {_, _} -> handle_get_buffer(Id, Req0);
        nomatch -> handle_get_metric(Id, Req0)
    end.

delete_route(_P, Id, Req0) ->
    handle_release_buffer(Id, Req0).

handle_record_metric(Req0) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req0),
    Params = cb_http_util:decode_json(Body),
    case cb_risk_capital:record_metric(Params) of
        {ok, M}         -> cb_http_util:reply_json(201, metric_to_map(M), Req1);
        {error, Reason} -> cb_http_util:reply_error(422, Reason, Req1)
    end.

handle_get_metric(MetricId, Req0) ->
    case cb_risk_capital:get_metric(MetricId) of
        {ok, M}            -> cb_http_util:reply_json(200, metric_to_map(M), Req0);
        {error, not_found} -> cb_http_util:reply_error(404, <<"not_found">>, Req0)
    end.

handle_list_metrics(Req0) ->
    QS         = cowboy_req:parse_qs(Req0),
    AccountId  = proplists:get_value(<<"account_id">>, QS, undefined),
    MetricType = binary_to_existing_atom(
                     proplists:get_value(<<"metric_type">>, QS, <<"credit_exposure">>), utf8),
    Metrics    = cb_risk_capital:list_metrics(AccountId, MetricType),
    cb_http_util:reply_json(200, [metric_to_map(M) || M <- Metrics], Req0).

handle_current_breaches(Req0) ->
    Breaches = cb_risk_capital:current_breaches(),
    cb_http_util:reply_json(200, [metric_to_map(M) || M <- Breaches], Req0).

handle_check_limit(Req0) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req0),
    Params     = cb_http_util:decode_json(Body),
    MetricType = binary_to_existing_atom(maps:get(<<"metric_type">>, Params), utf8),
    Value      = maps:get(<<"value">>, Params),
    Limit      = maps:get(<<"limit">>, Params),
    Result = cb_risk_capital:check_limit(MetricType, Value, Limit),
    Resp = case Result of
        ok                      -> #{result => <<"ok">>};
        {breach, V, L}          -> #{result => <<"breach">>, value => V, limit => L}
    end,
    cb_http_util:reply_json(200, Resp, Req1).

handle_allocate_buffer(Req0) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req0),
    Params = cb_http_util:decode_json(Body),
    case cb_risk_capital:allocate_buffer(Params) of
        {ok, B}         -> cb_http_util:reply_json(201, buffer_to_map(B), Req1);
        {error, Reason} -> cb_http_util:reply_error(422, Reason, Req1)
    end.

handle_get_buffer(BufferId, Req0) ->
    case cb_risk_capital:get_buffer(BufferId) of
        {ok, B}            -> cb_http_util:reply_json(200, buffer_to_map(B), Req0);
        {error, not_found} -> cb_http_util:reply_error(404, <<"not_found">>, Req0)
    end.

handle_list_buffers(Req0) ->
    Buffers = cb_risk_capital:list_buffers(),
    cb_http_util:reply_json(200, [buffer_to_map(B) || B <- Buffers], Req0).

handle_release_buffer(BufferId, Req0) ->
    case cb_risk_capital:release_buffer(BufferId) of
        ok              -> cb_http_util:reply_json(200, #{status => <<"released">>}, Req0);
        {error, Reason} -> cb_http_util:reply_error(422, Reason, Req0)
    end.

%%====================================================================
%% Serialization
%%====================================================================

metric_to_map(#risk_metric{
    metric_id = Id, account_id = AccountId, metric_type = Type,
    value = Value, limit_value = LimitValue, breached = Breached,
    measured_at = MeasuredAt, created_at = CreatedAt
}) ->
    #{
        metric_id   => Id,
        account_id  => AccountId,
        metric_type => Type,
        value       => Value,
        limit_value => LimitValue,
        breached    => Breached,
        measured_at => MeasuredAt,
        created_at  => CreatedAt
    }.

buffer_to_map(#capital_buffer{
    buffer_id = Id, buffer_type = Type, amount = Amount,
    currency = Ccy, effective_at = EffAt, updated_at = UpdatedAt
}) ->
    #{
        buffer_id    => Id,
        buffer_type  => Type,
        amount       => Amount,
        currency     => Ccy,
        effective_at => EffAt,
        updated_at   => UpdatedAt
    }.
