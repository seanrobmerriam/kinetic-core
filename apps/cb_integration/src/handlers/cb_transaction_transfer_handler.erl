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
