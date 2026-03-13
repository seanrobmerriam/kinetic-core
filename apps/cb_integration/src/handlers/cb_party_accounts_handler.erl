-module(cb_party_accounts_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    PartyId = cowboy_req:binding(<<"party_id">>, Req),
    handle(Method, PartyId, Req, State).

handle(<<"GET">>, PartyId, Req, State) ->
    Page = binary_to_integer(cowboy_req:binding(<<"page">>, Req, <<"1">>)),
    PageSize = binary_to_integer(cowboy_req:binding(<<"page_size">>, Req, <<"20">>)),
    case cb_accounts:list_accounts_for_party(PartyId, Page, PageSize) of
        {ok, Result} ->
            Resp = #{
                items => [account_to_json(A) || A <- maps:get(items, Result)],
                total => maps:get(total, Result),
                page => maps:get(page, Result),
                page_size => maps:get(page_size, Result)
            },
            Req2 = cowboy_req:reply(200, #{<<"content-type">> => <<"application/json">>}, jsone:encode(Resp), Req),
            {ok, Req2, State};
        {error, Reason} ->
            {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
            Resp = #{error => ErrorAtom, message => Message},
            Req2 = cowboy_req:reply(Status, #{<<"content-type">> => <<"application/json">>}, jsone:encode(Resp), Req),
            {ok, Req2, State}
    end;

handle(_, _PartyId, Req, State) ->
    Req2 = cowboy_req:reply(405, #{<<"content-type">> => <<"application/json">>}, <<"{\"error\": \"method_not_allowed\"}">>, Req),
    {ok, Req2, State}.

account_to_json(Account) ->
    #{
        account_id => Account#account.account_id,
        party_id => Account#account.party_id,
        name => Account#account.name,
        currency => Account#account.currency,
        balance => Account#account.balance,
        status => Account#account.status,
        created_at => Account#account.created_at,
        updated_at => Account#account.updated_at
    }.
