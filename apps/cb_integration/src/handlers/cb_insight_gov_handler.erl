%% @doc HTTP handler for governed insights (TASK-079).
%%
%% Routes:
%%   POST /api/v1/insights/insights
%%     body: {kind, generated_by, audience: [..]}
%%   GET  /api/v1/insights/insights?role=analyst|operator|risk_officer|admin
%%   GET  /api/v1/insights/insights/:id?accessor=...&role=...
%%   GET  /api/v1/insights/insights/:id/access-log
-module(cb_insight_gov_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").
-include_lib("cb_insights/include/cb_insights.hrl").

-export([init/2]).

init(Req, State) ->
    Method = cowboy_req:method(Req),
    Id     = cowboy_req:binding(id, Req),
    Action = cowboy_req:binding(action, Req),
    handle(Method, Id, Action, Req, State).

handle(<<"POST">>, undefined, undefined, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{kind := K, generated_by := Who, audience := A}, _}
                when is_binary(K), is_binary(Who), is_list(A) ->
            case parse_roles(A) of
                {error, invalid_role} ->
                    error_reply(400, <<"Invalid role in audience">>, Req2, State);
                {ok, Audience} ->
                    case cb_insight_gov:generate(binary_to_kind(K), Who, Audience) of
                        {ok, Id}        -> reply(201, #{insight_id => Id}, Req2, State);
                        {error, Reason} -> error_reply(400, Reason, Req2, State)
                    end
            end;
        _ ->
            error_reply(400, <<"Missing required fields">>, Req2, State)
    end;

handle(<<"GET">>, undefined, undefined, Req, State) ->
    Qs = cowboy_req:parse_qs(Req),
    case proplists:get_value(<<"role">>, Qs) of
        undefined ->
            error_reply(400, <<"Missing role query parameter">>, Req, State);
        RoleBin ->
            case binary_to_role(RoleBin) of
                {error, _} ->
                    error_reply(400, <<"Invalid role">>, Req, State);
                Role ->
                    Insights = cb_insight_gov:list_for_role(Role),
                    reply(200,
                          #{insights => [insight_to_map(I) || I <- Insights]},
                          Req, State)
            end
    end;

handle(<<"GET">>, Id, undefined, Req, State) ->
    Qs = cowboy_req:parse_qs(Req),
    case {proplists:get_value(<<"accessor">>, Qs),
          proplists:get_value(<<"role">>, Qs)} of
        {undefined, _} ->
            error_reply(400, <<"Missing accessor query parameter">>, Req, State);
        {_, undefined} ->
            error_reply(400, <<"Missing role query parameter">>, Req, State);
        {Accessor, RoleBin} ->
            case binary_to_role(RoleBin) of
                {error, _} ->
                    error_reply(400, <<"Invalid role">>, Req, State);
                Role ->
                    case cb_insight_gov:get(Id, Accessor, Role) of
                        {ok, I} ->
                            reply(200, insight_to_map(I), Req, State);
                        {error, not_found} ->
                            error_reply(404, <<"Insight not found">>, Req, State);
                        {error, Reason} ->
                            error_reply(403, Reason, Req, State)
                    end
            end
    end;

handle(<<"GET">>, Id, <<"access-log">>, Req, State) ->
    Logs = cb_insight_gov:list_access_log(Id),
    reply(200, #{logs => [log_to_map(L) || L <- Logs]}, Req, State);

handle(_, _, _, Req, State) ->
    error_reply(405, <<"Method not allowed">>, Req, State).

binary_to_role(<<"analyst">>)      -> analyst;
binary_to_role(<<"operator">>)     -> operator;
binary_to_role(<<"risk_officer">>) -> risk_officer;
binary_to_role(<<"admin">>)        -> admin;
binary_to_role(_)                  -> {error, invalid_role}.

-spec parse_roles([binary()]) -> {ok, [atom()]} | {error, invalid_role}.
parse_roles(Bins) ->
    lists:foldr(
        fun(_, {error, _} = Err) -> Err;
           (R, {ok, Acc}) ->
               case binary_to_role(R) of
                   {error, _} = Err -> Err;
                   Role             -> {ok, [Role | Acc]}
               end
        end,
        {ok, []},
        Bins
    ).

binary_to_kind(<<"segment_overview">>)       -> segment_overview;
binary_to_kind(<<"recommendation_summary">>) -> recommendation_summary;
binary_to_kind(<<"churn_summary">>)          -> churn_summary;
binary_to_kind(<<"drift_summary">>)          -> drift_summary;
binary_to_kind(_)                            -> unknown.

insight_to_map(I) ->
    #{insight_id   => I#insight.insight_id,
      kind         => I#insight.kind,
      sensitivity  => I#insight.sensitivity,
      payload      => I#insight.payload,
      generated_by => I#insight.generated_by,
      audience     => I#insight.audience,
      created_at   => I#insight.created_at}.

log_to_map(L) ->
    #{access_id   => L#insight_access_log.access_id,
      insight_id  => L#insight_access_log.insight_id,
      accessor    => L#insight_access_log.accessor,
      role        => L#insight_access_log.role,
      decision    => L#insight_access_log.decision,
      reason      => L#insight_access_log.reason,
      accessed_at => L#insight_access_log.accessed_at}.

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
