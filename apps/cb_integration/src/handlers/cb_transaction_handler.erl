%% @doc Single Transaction Handler
%%
%% Handler for the `/api/v1/transactions/:txn_id` endpoint for retrieving transactions.
%%
%% <h2>Purpose</h2>
%%
%% Retrieves detailed information about a specific transaction by its ID.
%% This is a read-only endpoint for transaction inquiry.
%%
%% <h2>REST API Endpoints</h2>
%%
%% <ul>
%%   <li><b>GET /api/v1/transactions/:txn_id</b> - Get transaction details</li>
%%   <li><b>OPTIONS /api/v1/transactions/:txn_id</b> - CORS preflight</li>
%% </ul>
%%
%% <h2>Response Format</h2>
%%
%% <pre>
%% {
%%   "txn_id": "uuid",
%%   "idempotency_key": "key",
%%   "txn_type": "transfer|deposit|withdrawal|...",
%%   "status": "pending|posted|reversed|failed",
%%   "amount": 10000,
%%   "currency": "USD",
%%   "source_account_id": "uuid",
%%   "dest_account_id": "uuid",
%%   "description": "...",
%%   "created_at": timestamp,
%%   "posted_at": timestamp
%% }
%% </pre>
%%
%% @see cb_payments
-module(cb_transaction_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    TxnId = cowboy_req:binding(txn_id, Req),
    handle(Method, TxnId, Req, State).

handle(<<"GET">>, TxnId, Req, State) ->
    case cb_payments:get_transaction(TxnId) of
        {ok, Txn} ->
            Resp = transaction_to_json(Txn),
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

handle(<<"OPTIONS">>, _TxnId, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _TxnId, Req, State) ->
    {_Code405, _Hdrs405, _Body405} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(_Code405, _Hdrs405, _Body405, Req),
    {ok, Req2, State}.

transaction_to_json(Txn) ->
    #{
        txn_id => Txn#transaction.txn_id,
        idempotency_key => Txn#transaction.idempotency_key,
        txn_type => Txn#transaction.txn_type,
        status => Txn#transaction.status,
        amount => Txn#transaction.amount,
        currency => Txn#transaction.currency,
        source_account_id => Txn#transaction.source_account_id,
        dest_account_id => Txn#transaction.dest_account_id,
        description => Txn#transaction.description,
        created_at => Txn#transaction.created_at,
        posted_at => Txn#transaction.posted_at
    }.
