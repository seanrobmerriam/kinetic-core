-module(cb_party_accounts_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    PartyId = cowboy_req:binding(party_id, Req),
    handle(Method, PartyId, Req, State).

handle(<<"GET">>, PartyId, Req, State) ->
    Qs = cowboy_req:parse_qs(Req),
    Page = binary_to_integer(proplists:get_value(<<"page">>, Qs, <<"1">>)),
    PageSize = binary_to_integer(proplists:get_value(<<"page_size">>, Qs, <<"20">>)),
    case cb_accounts:list_accounts_for_party(PartyId, Page, PageSize) of
        {ok, Result} ->
            Resp = #{
                items => [account_to_json(A) || A <- maps:get(items, Result)],
                total => maps:get(total, Result),
                page => maps:get(page, Result),
                page_size => maps:get(page_size, Result)
            },
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State};
        {error, Reason} ->
            {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
            Resp = #{error => ErrorAtom, message => Message},
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State}
    end;

handle(<<"OPTIONS">>, _PartyId, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _PartyId, Req, State) ->
    {_Code405, _Hdrs405, _Body405} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(_Code405, _Hdrs405, _Body405, Req),
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
