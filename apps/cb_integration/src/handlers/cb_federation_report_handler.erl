%% @doc HTTP handler for Federated Reporting API (TASK-065)
%%
%% Routes:
%%   POST   /api/v1/reports/federation          — submit report job
%%   GET    /api/v1/reports/federation          — list reports (query: requested_by)
%%   GET    /api/v1/reports/federation/:id      — get report
%%   POST   /api/v1/reports/federation/:id/run  — run report synchronously
-module(cb_federation_report_handler).

-include("../../cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

init(Req0, State) ->
    Method   = cowboy_req:method(Req0),
    PathInfo = cowboy_req:path_info(Req0),
    {ok, Req} = handle(Method, PathInfo, Req0),
    {ok, Req, State}.

handle(<<"POST">>, [],           Req0) -> handle_submit(Req0);
handle(<<"GET">>,  [],           Req0) -> handle_list(Req0);
handle(<<"GET">>,  [Id],         Req0) -> handle_get(Id, Req0);
handle(<<"POST">>, [Id, <<"run">>], Req0) -> handle_run(Id, Req0);
handle(_,          _,            Req0) -> cb_http_util:reply_error(405, <<"method_not_allowed">>, Req0).

handle_submit(Req0) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req0),
    Params = cb_http_util:decode_json(Body),
    case cb_federation_report:submit(Params) of
        {ok, Report}    -> cb_http_util:reply_json(201, report_to_map(Report), Req1);
        {error, Reason} -> cb_http_util:reply_error(422, Reason, Req1)
    end.

handle_list(Req0) ->
    QS          = cowboy_req:parse_qs(Req0),
    RequestedBy = proplists:get_value(<<"requested_by">>, QS, undefined),
    Reports     = cb_federation_report:list_reports(RequestedBy),
    cb_http_util:reply_json(200, [report_to_map(R) || R <- Reports], Req0).

handle_get(ReportId, Req0) ->
    case cb_federation_report:get_report(ReportId) of
        {ok, Report}       -> cb_http_util:reply_json(200, report_to_map(Report), Req0);
        {error, not_found} -> cb_http_util:reply_error(404, <<"not_found">>, Req0)
    end.

handle_run(ReportId, Req0) ->
    case cb_federation_report:run(ReportId) of
        {ok, Report}    -> cb_http_util:reply_json(200, report_to_map(Report), Req0);
        {error, Reason} -> cb_http_util:reply_error(422, Reason, Req0)
    end.

%%====================================================================
%% Serialization
%%====================================================================

report_to_map(#federation_report{
    report_id = Id, report_type = Type, params = Params,
    status = Status, result = Result, error = Err,
    requested_by = ReqBy, requested_at = ReqAt, completed_at = CompletedAt
}) ->
    #{
        report_id    => Id,
        report_type  => Type,
        params       => Params,
        status       => Status,
        result       => Result,
        error        => Err,
        requested_by => ReqBy,
        requested_at => ReqAt,
        completed_at => CompletedAt
    }.
