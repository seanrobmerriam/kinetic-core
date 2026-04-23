%% @doc HTTP handler: GET/POST /v1/stp/rules and GET/PUT/DELETE /v1/stp/rules/:id
-module(cb_stp_rules_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

init(Req, State) ->
    Method = cowboy_req:method(Req),
    RuleId = cowboy_req:binding(rule_id, Req),
    handle(Method, RuleId, Req, State).

handle(<<"GET">>, undefined, Req, State) ->
    Rules = cb_stp_rules:list_rules(),
    Req2 = cowboy_req:reply(200, headers(),
               jsone:encode(#{rules => [rule_to_map(R) || R <- Rules]}), Req),
    {ok, Req2, State};

handle(<<"POST">>, undefined, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{name := Name, priority := Priority,
               condition_type := CondType,
               condition_params := Params,
               action := Action} = _P, _} ->
            CT = binary_to_existing_atom(CondType, utf8),
            Act = binary_to_existing_atom(Action, utf8),
            case cb_stp_rules:create_rule(Name, Priority, CT,
                                          maps:from_list(maps:to_list(Params)), Act) of
                {ok, Rule} ->
                    Req3 = cowboy_req:reply(201, headers(),
                               jsone:encode(rule_to_map(Rule)), Req2),
                    {ok, Req3, State};
                {error, Reason} ->
                    {Code, _, Msg} = cb_http_errors:to_response(Reason),
                    Req3 = cowboy_req:reply(Code, headers(),
                               jsone:encode(#{error => Reason, message => Msg}), Req2),
                    {ok, Req3, State}
            end;
        _ ->
            Req3 = cowboy_req:reply(400, headers(),
                       jsone:encode(#{error => <<"bad_request">>,
                                      message => <<"Missing required fields">>}), Req2),
            {ok, Req3, State}
    end;

handle(<<"GET">>, RuleId, Req, State) ->
    case cb_stp_rules:get_rule(RuleId) of
        {ok, Rule} ->
            Req2 = cowboy_req:reply(200, headers(),
                       jsone:encode(rule_to_map(Rule)), Req),
            {ok, Req2, State};
        {error, not_found} ->
            Req2 = cowboy_req:reply(404, headers(),
                       jsone:encode(#{error => <<"not_found">>}), Req),
            {ok, Req2, State}
    end;

handle(<<"PUT">>, RuleId, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, Params, _} ->
            Updates = maps:fold(fun(K, V, Acc) ->
                maps:put(K, V, Acc)
            end, #{}, Params),
            case cb_stp_rules:update_rule(RuleId, Updates) of
                {ok, Rule} ->
                    Req3 = cowboy_req:reply(200, headers(),
                               jsone:encode(rule_to_map(Rule)), Req2),
                    {ok, Req3, State};
                {error, not_found} ->
                    Req3 = cowboy_req:reply(404, headers(),
                               jsone:encode(#{error => <<"not_found">>}), Req2),
                    {ok, Req3, State};
                {error, Reason} ->
                    {Code, _, Msg} = cb_http_errors:to_response(Reason),
                    Req3 = cowboy_req:reply(Code, headers(),
                               jsone:encode(#{error => Reason, message => Msg}), Req2),
                    {ok, Req3, State}
            end;
        _ ->
            Req3 = cowboy_req:reply(400, headers(),
                       jsone:encode(#{error => <<"bad_request">>}), Req2),
            {ok, Req3, State}
    end;

handle(<<"DELETE">>, RuleId, Req, State) ->
    case cb_stp_rules:delete_rule(RuleId) of
        ok ->
            Req2 = cowboy_req:reply(204, headers(), <<>>, Req),
            {ok, Req2, State};
        {error, not_found} ->
            Req2 = cowboy_req:reply(404, headers(),
                       jsone:encode(#{error => <<"not_found">>}), Req),
            {ok, Req2, State}
    end;

handle(_, _, Req, State) ->
    Req2 = cowboy_req:reply(405, headers(), <<>>, Req),
    {ok, Req2, State}.

rule_to_map(#stp_routing_rule{
    rule_id = Id, name = Name, priority = Prio,
    condition_type = CT, condition_params = Params,
    action = Action, enabled = Enabled,
    created_at = CreAt, updated_at = UpdAt
}) ->
    #{
        rule_id          => Id,
        name             => Name,
        priority         => Prio,
        condition_type   => CT,
        condition_params => Params,
        action           => Action,
        enabled          => Enabled,
        created_at       => CreAt,
        updated_at       => UpdAt
    }.

headers() ->
    maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()).
