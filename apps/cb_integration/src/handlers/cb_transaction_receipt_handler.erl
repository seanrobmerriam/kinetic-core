%% @doc Handler for GET /api/v1/transactions/:txn_id/receipt
%%
%% Returns a structured receipt for a single transaction, including the
%% transaction metadata and its associated double-entry ledger lines.
-module(cb_transaction_receipt_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    TxnId  = cowboy_req:binding(txn_id, Req),
    handle(Method, TxnId, Req, State).

handle(<<"GET">>, TxnId, Req, State) ->
    with_transaction(TxnId, Req, State, fun(Txn) ->
        case cb_ledger:get_entries_for_transaction(TxnId) of
            {ok, Entries} ->
                Receipt = #{
                    txn_id            => Txn#transaction.txn_id,
                    txn_type          => Txn#transaction.txn_type,
                    status            => Txn#transaction.status,
                    amount            => Txn#transaction.amount,
                    currency          => Txn#transaction.currency,
                    source_account_id => Txn#transaction.source_account_id,
                    dest_account_id   => Txn#transaction.dest_account_id,
                    description       => Txn#transaction.description,
                    channel           => Txn#transaction.channel,
                    created_at        => Txn#transaction.created_at,
                    posted_at         => Txn#transaction.posted_at,
                    ledger_entries    => [entry_to_json(E) || E <- Entries]
                },
                Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                cowboy_req:reply(200, Headers, jsone:encode(Receipt), Req);
            {error, Reason} ->
                {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
                Resp = #{error => ErrorAtom, message => Message},
                Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req)
        end
    end);

handle(<<"OPTIONS">>, _TxnId, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _TxnId, Req, State) ->
    {_Code405, _Hdrs405, _Body405} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(_Code405, _Hdrs405, _Body405, Req),
    {ok, Req2, State}.

with_transaction(TxnId, Req, State, Fun) ->
    case cb_payments:get_transaction(TxnId) of
        {ok, Txn} ->
            Req2 = Fun(Txn),
            {ok, Req2, State};
        {error, Reason} ->
            {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
            Resp = #{error => ErrorAtom, message => Message},
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State}
    end.

entry_to_json(Entry) ->
    #{
        entry_id   => Entry#ledger_entry.entry_id,
        txn_id     => Entry#ledger_entry.txn_id,
        account_id => Entry#ledger_entry.account_id,
        entry_type => Entry#ledger_entry.entry_type,
        amount     => Entry#ledger_entry.amount,
        currency   => Entry#ledger_entry.currency,
        description=> Entry#ledger_entry.description,
        posted_at  => Entry#ledger_entry.posted_at
    }.
