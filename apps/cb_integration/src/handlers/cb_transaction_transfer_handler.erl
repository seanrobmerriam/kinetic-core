%% @doc Transfer Transaction Handler
%%
%% Handler for the `/api/v1/transactions/transfer` endpoint for money transfers.
%%
%% <h2>What is a Transfer?</h2>
%%
%% A transfer moves money from one account to another within the banking system.
%% It's a fundamental transaction type that:
%% <ul>
%%   <li>Debits the source account</li>
%%   <li>Credits the destination account</li>
%%   <li>Creates corresponding ledger entries for double-entry bookkeeping</li>
%% </ul>
%%
%% <h2>Idempotency</h2>
%%
%% This endpoint supports idempotency via the idempotency_key field. This is critical
%% for financial transactions where network failures can cause duplicate submissions.
%% If the same idempotency_key is used for a second request, the original transaction
%% is returned instead of creating a duplicate.
%%
%% <h2>REST API Endpoints</h2>
%%
%% <ul>
%%   <li><b>POST /api/v1/transactions/transfer</b> - Create a transfer</li>
%%   <li><b>OPTIONS /api/v1/transactions/transfer</b> - CORS preflight</li>
%% </ul>
%%
%% <h2>Request Format</h2>
%%
%% <pre>
%% {
%%   "idempotency_key": "unique-key-123",
%%   "source_account_id": "uuid",
%%   "dest_account_id": "uuid",
%%   "amount": 10000,
%%   "currency": "USD",
%%   "description": "Payment for invoice #123"
%% }
%% </pre>
%%
%% Required fields:
%% <ul>
%%   <li><code>idempotency_key</code> - Unique key for idempotency</li>
%%   <li><code>source_account_id</code> - Source account UUID</li>
%%   <li><code>dest_account_id</code> - Destination account UUID</li>
%%   <li><code>amount</code> - Amount in minor units (e.g., $100.00 = 10000)</li>
%%   <li><code>currency</code> - ISO 4217 currency code</li>
%%   <li><code>description</code> - Transaction description</li>
%% </ul>
%%
%% @see cb_payments
-module(cb_transaction_transfer_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    handle(Method, Req, State).

handle(<<"POST">>, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body) of
        {ok, #{
            <<"idempotency_key">> := IdempotencyKey,
            <<"source_account_id">> := SourceId,
            <<"dest_account_id">> := DestId,
            <<"amount">> := Amount,
            <<"currency">> := CurrencyBin,
            <<"description">> := Description
        }, _} ->
            Currency = binary_to_existing_atom(CurrencyBin, utf8),
            case cb_payments:transfer(IdempotencyKey, SourceId, DestId, Amount, Currency, Description) of
                {ok, Txn} ->
                    Resp = transaction_to_json(Txn),
                    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                    Req3 = cowboy_req:reply(201, Headers, jsone:encode(Resp), Req2),
                    {ok, Req3, State};
                {error, Reason} ->
                    {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
                    Resp = #{error => ErrorAtom, message => Message},
                    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                    Req3 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req2),
                    {ok, Req3, State}
            end;
        _ ->
            {Status, ErrorAtom, Message} = cb_http_errors:to_response(missing_required_field),
            Resp = #{error => ErrorAtom, message => Message},
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req3 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req2),
            {ok, Req3, State}
    end;

handle(<<"OPTIONS">>, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, Req, State) ->
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
