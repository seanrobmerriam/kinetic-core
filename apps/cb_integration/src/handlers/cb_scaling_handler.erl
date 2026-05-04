%% @doc HTTP handler for autoscaling rule management (TASK-068).
%%
%% Routes (see cb_router.erl):
%%   GET    /api/v1/scaling/rules                     → list rules
%%   POST   /api/v1/scaling/rules                     → add rule
%%   GET    /api/v1/scaling/rules/:rule_id            → get rule
%%   PUT    /api/v1/scaling/rules/:rule_id            → update rule
%%   DELETE /api/v1/scaling/rules/:rule_id            → delete rule
%%   POST   /api/v1/scaling/rules/:rule_id/enable     → enable rule
%%   POST   /api/v1/scaling/rules/:rule_id/disable    → disable rule
%%   POST   /api/v1/scaling/metrics                   → record metric sample
%%   GET    /api/v1/scaling/evaluate                  → evaluate rules now
-module(cb_scaling_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-define(JSON, #{<<"content-type">> => <<"application/json">>}).

init(Req, State) ->
    Method = cowboy_req:method(Req),
    RuleId = cowboy_req:binding(rule_id, Req),
    Action = cowboy_req:binding(action, Req),
    handle(Method, RuleId, Action, Req, State).

%% Rule sub-actions (enable / disable)
handle(<<"POST">>, RuleId, <<"enable">>, Req, State) when RuleId =/= undefined ->
    case cb_scaling:enable_rule(RuleId) of
        ok                 -> reply(200, #{status => <<"enabled">>}, Req, State);
        {error, not_found} -> error_reply(404, <<"not_found">>, <<"Rule not found">>, Req, State)
    end;

handle(<<"POST">>, RuleId, <<"disable">>, Req, State) when RuleId =/= undefined ->
    case cb_scaling:disable_rule(RuleId) of
        ok                 -> reply(200, #{status => <<"disabled">>}, Req, State);
        {error, not_found} -> error_reply(404, <<"not_found">>, <<"Rule not found">>, Req, State)
    end;

%% GET /api/v1/scaling/rules/:rule_id
handle(<<"GET">>, RuleId, undefined, Req, State) when RuleId =/= undefined ->
    case cb_scaling:get_rule(RuleId) of
        {ok, Rule}         -> reply(200, rule_to_map(Rule), Req, State);
        {error, not_found} -> error_reply(404, <<"not_found">>, <<"Rule not found">>, Req, State)
    end;

%% PUT /api/v1/scaling/rules/:rule_id
handle(<<"PUT">>, RuleId, undefined, Req0, State) when RuleId =/= undefined ->
    {ok, Body, Req} = cowboy_req:read_body(Req0),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, Params, _} ->
            case cb_scaling:update_rule(RuleId, Params) of
                ok                 -> reply(200, #{status => <<"updated">>}, Req, State);
                {error, not_found} -> error_reply(404, <<"not_found">>, <<"Rule not found">>, Req, State)
            end;
        {error, _} ->
            error_reply(400, <<"invalid_json">>, <<"Invalid JSON body">>, Req, State)
    end;

%% DELETE /api/v1/scaling/rules/:rule_id
handle(<<"DELETE">>, RuleId, undefined, Req, State) when RuleId =/= undefined ->
    case cb_scaling:delete_rule(RuleId) of
        ok                 -> reply(204, #{}, Req, State);
        {error, not_found} -> error_reply(404, <<"not_found">>, <<"Rule not found">>, Req, State)
    end;

%% GET /api/v1/scaling/rules
handle(<<"GET">>, undefined, undefined, Req, State) ->
    case cowboy_req:path(Req) of
        <<"/api/v1/scaling/evaluate">> ->
            Triggered = cb_scaling:evaluate_rules(),
            Payload   = [#{rule_id => RId,
                           direction => atom_to_binary(Dir, utf8)}
                         || {RId, Dir} <- Triggered],
            reply(200, #{triggered => Payload}, Req, State);
        _ ->
            Rules = cb_scaling:list_rules(),
            reply(200, #{rules => [rule_to_map(R) || R <- Rules]}, Req, State)
    end;

%% POST /api/v1/scaling/metrics
handle(<<"POST">>, undefined, undefined, Req0, State) ->
    case cowboy_req:path(Req0) of
        <<"/api/v1/scaling/metrics">> ->
            {ok, Body, Req} = cowboy_req:read_body(Req0),
            case jsone:try_decode(Body, [{keys, atom}]) of
                {ok, #{metric_name := Metric, value := Value}, _} ->
                    {ok, SampleId} = cb_scaling:record_metric(Metric, Value),
                    reply(201, #{sample_id => SampleId}, Req, State);
                {ok, _, _} ->
                    error_reply(400, <<"missing_field">>, <<"metric_name and value required">>, Req0, State);
                {error, _} ->
                    error_reply(400, <<"invalid_json">>, <<"Invalid JSON body">>, Req0, State)
            end;
        _ ->
            %% POST /api/v1/scaling/rules
            {ok, Body, Req} = cowboy_req:read_body(Req0),
            case jsone:try_decode(Body, [{keys, atom}]) of
                {ok, Params, _} ->
                    Required = [name, metric_name, threshold, direction, cooldown_seconds],
                    case validate_required(Params, Required) of
                        ok ->
                            Dir = binary_to_atom(maps:get(direction, Params), utf8),
                            Input = maps:put(direction, Dir, Params),
                            case cb_scaling:add_rule(Input) of
                                {ok, RuleId}    -> reply(201, #{rule_id => RuleId}, Req, State);
                                {error, Reason} -> error_reply(422, Reason, <<"Rule creation failed">>, Req, State)
                            end;
                        {missing, Field} ->
                            Msg = iolist_to_binary([<<"Missing field: ">>, atom_to_binary(Field, utf8)]),
                            error_reply(400, <<"missing_field">>, Msg, Req, State)
                    end;
                {error, _} ->
                    error_reply(400, <<"invalid_json">>, <<"Invalid JSON body">>, Req, State)
            end
    end;

handle(_, _, _, Req, State) ->
    error_reply(405, <<"method_not_allowed">>, <<"Method not allowed">>, Req, State).

%%--------------------------------------------------------------------
%% Internal
%%--------------------------------------------------------------------

rule_to_map(#scaling_rule{
        rule_id           = Id,
        name              = Name,
        metric_name       = Metric,
        threshold         = Threshold,
        direction         = Direction,
        cooldown_seconds  = Cooldown,
        enabled           = Enabled,
        last_triggered_at = LastAt,
        created_at        = CreatedAt,
        updated_at        = UpdatedAt}) ->
    #{rule_id           => Id,
      name              => Name,
      metric_name       => Metric,
      threshold         => Threshold,
      direction         => atom_to_binary(Direction, utf8),
      cooldown_seconds  => Cooldown,
      enabled           => Enabled,
      last_triggered_at => LastAt,
      created_at        => CreatedAt,
      updated_at        => UpdatedAt}.

validate_required(Params, Fields) ->
    case [F || F <- Fields, not maps:is_key(F, Params)] of
        []        -> ok;
        [First|_] -> {missing, First}
    end.

reply(Status, Body, Req, State) ->
    Resp = cowboy_req:reply(Status, ?JSON, jsone:encode(Body), Req),
    {ok, Resp, State}.

error_reply(Status, Reason, Message, Req, State) ->
    ReasonBin = if is_atom(Reason)   -> atom_to_binary(Reason, utf8);
                   is_binary(Reason) -> Reason;
                   true              -> iolist_to_binary(io_lib:format("~p", [Reason]))
                end,
    reply(Status, #{error => ReasonBin, message => Message}, Req, State).
