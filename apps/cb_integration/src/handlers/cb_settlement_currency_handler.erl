%% @doc Settlement Currency Handler
%%
%% Handler for transaction settlement currency operations.
%%
%% <h2>REST API Endpoints</h2>
%%
%% <ul>
%%   <li><b>GET /api/v1/transactions/:txn_id/settlement-currency</b> — Get current settlement currency</li>
%%   <li><b>PUT /api/v1/transactions/:txn_id/settlement-currency</b> — Set/update settlement currency</li>
%%   <li><b>OPTIONS</b> — CORS preflight</li>
%% </ul>
%%
-module(cb_settlement_currency_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    TxnId = cowboy_req:binding(txn_id, Req),
    handle(Method, TxnId, Req, State).

%% GET /api/v1/transactions/:txn_id/settlement-currency
handle(<<"GET">>, TxnId, Req, State) ->
    case cb_settlement_currency:get_settlement_currency(TxnId) of
        {ok, SettlementCurrency} ->
            Resp = #{
                txn_id => TxnId,
                settlement_currency => case SettlementCurrency of
                    undefined -> null;
                    C -> atom_to_binary(C, utf8)
                end
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

%% PUT /api/v1/transactions/:txn_id/settlement-currency
handle(<<"PUT">>, TxnId, Req, State) ->
    case jsone:decode(Req) of
        {ok, Body, Req1} ->
            CurrencyBin = maps:get(<<"settlement_currency">>, Body),
            case cb_validate:currency(CurrencyBin) of
                {error, CurrErr} ->
                    {ErrStatus, ErrAtom, ErrMsg} = cb_http_errors:to_response(CurrErr),
                    ErrResp = #{error => ErrAtom, message => ErrMsg},
                    ErrHeaders = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                    Req2 = cowboy_req:reply(ErrStatus, ErrHeaders, jsone:encode(ErrResp), Req1),
                    {ok, Req2, State};
                ok ->
                    Currency = binary_to_existing_atom(CurrencyBin, utf8),
                    case cb_settlement_currency:assign_settlement_currency(TxnId, Currency) of
                        {ok, Txn} ->
                            Resp = #{
                                txn_id => Txn#transaction.txn_id,
                                settlement_currency => case Txn#transaction.settlement_currency of
                                    undefined -> null;
                                    C -> atom_to_binary(C, utf8)
                                end
                            },
                            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                            Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req1),
                            {ok, Req2, State};
                        {error, Reason} ->
                            {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
                            Resp = #{error => ErrorAtom, message => Message},
                            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                            Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req1),
                            {ok, Req2, State}
                    end
            end;
        {error, _} ->
            {Code, Hdrs, Body} = cb_http_errors:to_response_with_metrics(bad_request),
            Req2 = cowboy_req:reply(Code, Hdrs, Body, Req),
            {ok, Req2, State}
    end;

handle(<<"OPTIONS">>, _TxnId, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _TxnId, Req, State) ->
    {_Code405, _Hdrs405, _Body405} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(_Code405, _Hdrs405, _Body405, Req),
    {ok, Req2, State}.