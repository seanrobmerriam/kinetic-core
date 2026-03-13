-module(cb_account_balance_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    AccountId = cowboy_req:binding(<<"account_id">>, Req),
    handle(Method, AccountId, Req, State).

handle(<<"GET">>, AccountId, Req, State) ->
    case cb_accounts:get_balance(AccountId) of
        {ok, Result} ->
            Req2 = cowboy_req:reply(200, #{<<"content-type">> => <<"application/json">>}, jsone:encode(Result), Req),
            {ok, Req2, State};
        {error, Reason} ->
            {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
            Resp = #{error => ErrorAtom, message => Message},
            Req2 = cowboy_req:reply(Status, #{<<"content-type">> => <<"application/json">>}, jsone:encode(Resp), Req),
            {ok, Req2, State}
    end;

handle(_, _AccountId, Req, State) ->
    Req2 = cowboy_req:reply(405, #{<<"content-type">> => <<"application/json">>}, <<"{\"error\": \"method_not_allowed\"}">>, Req),
    {ok, Req2, State}.
