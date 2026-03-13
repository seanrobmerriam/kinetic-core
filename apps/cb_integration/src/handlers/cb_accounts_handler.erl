-module(cb_accounts_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    handle(Method, Req, State).

handle(<<"POST">>, Req, State) ->
    %% Create account
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body) of
        {ok, #{<<"party_id">> := PartyId, <<"currency">> := CurrencyBin, <<"name">> := Name}, _} ->
            Currency = binary_to_existing_atom(CurrencyBin, utf8),
            case cb_accounts:create_account(PartyId, Name, Currency) of
                {ok, Account} ->
                    Resp = account_to_json(Account),
                    Req3 = cowboy_req:reply(201, #{<<"content-type">> => <<"application/json">>}, jsone:encode(Resp), Req2),
                    {ok, Req3, State};
                {error, Reason} ->
                    {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
                    Resp = #{error => ErrorAtom, message => Message},
                    Req3 = cowboy_req:reply(Status, #{<<"content-type">> => <<"application/json">>}, jsone:encode(Resp), Req2),
                    {ok, Req3, State}
            end;
        _ ->
            {Status, ErrorAtom, Message} = cb_http_errors:to_response(missing_required_field),
            Resp = #{error => ErrorAtom, message => Message},
            Req3 = cowboy_req:reply(Status, #{<<"content-type">> => <<"application/json">>}, jsone:encode(Resp), Req2),
            {ok, Req3, State}
    end;

handle(_, Req, State) ->
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
