%% @doc HTTP handler: GET/PATCH /aml/suspicious-activity/:alert_id
-module(cb_suspicious_activity_item_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

init(Req, State) ->
    Method = cowboy_req:method(Req),
    AlertId = cowboy_req:binding(alert_id, Req),
    handle(Method, AlertId, Req, State).

handle(<<"GET">>, AlertId, Req, State) ->
    case cb_aml:get_alert(AlertId) of
        {ok, Alert} ->
            Req2 = cowboy_req:reply(200, headers(), jsone:encode(alert_to_map(Alert)), Req),
            {ok, Req2, State};
        {error, Reason} ->
            reply_error(Reason, Req, State)
    end;
handle(<<"PATCH">>, AlertId, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, Params, _} ->
            DecisionStr = maps:get(decision, Params, undefined),
            ReviewerId  = maps:get(reviewer_id, Params, <<"system">>),
            Decision = case DecisionStr of
                <<"cleared">>   -> cleared;
                <<"escalated">> -> escalated;
                A when is_atom(A), A =/= undefined -> A;
                _ -> undefined
            end,
            case Decision of
                undefined ->
                    Req3 = cowboy_req:reply(422, headers(), jsone:encode(#{error => <<"missing_decision">>, message => <<"decision must be cleared or escalated">>}), Req2),
                    {ok, Req3, State};
                _ ->
                    case cb_aml:review_alert(AlertId, Decision, ReviewerId) of
                        {ok, Alert} ->
                            Req3 = cowboy_req:reply(200, headers(), jsone:encode(alert_to_map(Alert)), Req2),
                            {ok, Req3, State};
                        {error, Reason} ->
                            {Code, _Atom, Msg} = cb_http_errors:to_response(Reason),
                            Req3 = cowboy_req:reply(Code, headers(), jsone:encode(#{error => Reason, message => Msg}), Req2),
                            {ok, Req3, State}
                    end
            end;
        {error, _} ->
            Req3 = cowboy_req:reply(400, headers(), jsone:encode(#{error => <<"bad_request">>, message => <<"Invalid JSON">>}), Req2),
            {ok, Req3, State}
    end;
handle(_, _, Req, State) ->
    Req2 = cowboy_req:reply(405, headers(), <<>>, Req),
    {ok, Req2, State}.

reply_error(Reason, Req, State) ->
    {Code, _Atom, Msg} = cb_http_errors:to_response(Reason),
    Req2 = cowboy_req:reply(Code, headers(), jsone:encode(#{error => Reason, message => Msg}), Req),
    {ok, Req2, State}.

alert_to_map(#suspicious_activity{
    alert_id = AId, party_id = PId, txn_id = TId, rule_id = RId,
    reason = Reason, status = Status, risk_score = RS, metadata = Meta,
    reviewed_by = RevBy, reviewed_at = RevAt, created_at = CreAt, updated_at = UpdAt
}) ->
    #{alert_id => AId, party_id => PId, txn_id => TId, rule_id => RId,
      reason => Reason, status => Status, risk_score => RS, metadata => Meta,
      reviewed_by => RevBy, reviewed_at => RevAt, created_at => CreAt, updated_at => UpdAt}.

headers() ->
    maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()).
