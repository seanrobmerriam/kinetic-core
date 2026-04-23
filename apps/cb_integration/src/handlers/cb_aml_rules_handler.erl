%% @doc HTTP handler: POST/GET /aml/rules
-module(cb_aml_rules_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

init(Req, State) ->
    Method = cowboy_req:method(Req),
    handle(Method, Req, State).

handle(<<"POST">>, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, Params, _} ->
            case cb_aml:create_rule(Params) of
                {ok, Rule} ->
                    Req3 = cowboy_req:reply(201, headers(), jsone:encode(rule_to_map(Rule)), Req2),
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
handle(<<"GET">>, Req, State) ->
    {ok, Rules} = cb_aml:list_rules(),
    Req2 = cowboy_req:reply(200, headers(), jsone:encode(#{rules => [rule_to_map(R) || R <- Rules]}), Req),
    {ok, Req2, State};
handle(_, Req, State) ->
    Req2 = cowboy_req:reply(405, headers(), <<>>, Req),
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
