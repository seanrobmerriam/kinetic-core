%% @doc HTTP handler: GET/PUT/DELETE /aml/rules/:rule_id
-module(cb_aml_rule_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

init(Req, State) ->
    Method = cowboy_req:method(Req),
    RuleId = cowboy_req:binding(rule_id, Req),
    handle(Method, RuleId, Req, State).

handle(<<"GET">>, RuleId, Req, State) ->
    case cb_aml:get_rule(RuleId) of
        {ok, Rule} ->
            Req2 = cowboy_req:reply(200, headers(), jsone:encode(rule_to_map(Rule)), Req),
            {ok, Req2, State};
        {error, Reason} ->
            reply_error(Reason, Req, State)
    end;
handle(<<"PUT">>, RuleId, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, Params, _} ->
            case cb_aml:update_rule(RuleId, Params) of
                {ok, Rule} ->
                    Req3 = cowboy_req:reply(200, headers(), jsone:encode(rule_to_map(Rule)), Req2),
                    {ok, Req3, State};
                {error, Reason} ->
                    {Code, _Atom, Msg} = cb_http_errors:to_response(Reason),
                    Req3 = cowboy_req:reply(Code, headers(), jsone:encode(#{error => Reason, message => Msg}), Req2),
                    {ok, Req3, State}
            end;
        {error, _} ->
            Req3 = cowboy_req:reply(400, headers(), jsone:encode(#{error => <<"bad_request">>, message => <<"Invalid JSON">>}), Req2),
            {ok, Req3, State}
    end;
handle(<<"DELETE">>, RuleId, Req, State) ->
    case cb_aml:delete_rule(RuleId) of
        ok ->
            Req2 = cowboy_req:reply(204, headers(), <<>>, Req),
            {ok, Req2, State};
        {error, Reason} ->
            reply_error(Reason, Req, State)
    end;
handle(_, _, Req, State) ->
    Req2 = cowboy_req:reply(405, headers(), <<>>, Req),
    {ok, Req2, State}.

reply_error(Reason, Req, State) ->
    {Code, _Atom, Msg} = cb_http_errors:to_response(Reason),
    Req2 = cowboy_req:reply(Code, headers(), jsone:encode(#{error => Reason, message => Msg}), Req),
    {ok, Req2, State}.

rule_to_map(#aml_rule{
    rule_id = RId, name = Name, description = Desc,
    condition_type = CT, threshold_value = TV, action = Act,
    enabled = Enabled, version = Ver, created_at = CreAt, updated_at = UpdAt
}) ->
    #{rule_id => RId, name => Name, description => Desc,
      condition_type => CT, threshold_value => TV, action => Act,
      enabled => Enabled, version => Ver, created_at => CreAt, updated_at => UpdAt}.

headers() ->
    maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()).
