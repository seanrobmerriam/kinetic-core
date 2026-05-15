%% @doc Payment Cancel Handler
%%
%% Handler for `POST /api/v1/payment-orders/:payment_id/cancel`.
%%
%% Cancels a payment order that is still in `initiated` or `validating` state.
-module(cb_payment_cancel_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    PaymentId = cowboy_req:binding(payment_id, Req),
    handle(Method, PaymentId, Req, State).

handle(<<"POST">>, PaymentId, Req, State) ->
    case cb_payment_orders:cancel_payment(PaymentId) of
        {ok, Order} ->
            Resp = payment_to_json(Order),
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

handle(<<"OPTIONS">>, _PaymentId, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _PaymentId, Req, State) ->
    {_Code405, _Hdrs405, _Body405} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(_Code405, _Hdrs405, _Body405, Req),
    {ok, Req2, State}.

payment_to_json(Order) ->
    #{
        payment_id => Order#payment_order.payment_id,
        party_id => Order#payment_order.party_id,
        source_account_id => Order#payment_order.source_account_id,
        dest_account_id => Order#payment_order.dest_account_id,
        amount => Order#payment_order.amount,
        currency => atom_to_binary(Order#payment_order.currency, utf8),
        description => Order#payment_order.description,
        status => Order#payment_order.status,
        failure_reason => Order#payment_order.failure_reason,
        retry_count => Order#payment_order.retry_count,
        created_at => Order#payment_order.created_at,
        updated_at => Order#payment_order.updated_at
    }.