%% @doc Payment Orders HTTP Handler
%%
%% Handles the payment order lifecycle API:
%% - GET /api/v1/payment-orders - list all payment orders
%% - POST /api/v1/payment-orders - initiate a new payment order
%% - GET /api/v1/payment-orders/:payment_id - get order by ID
%% - POST /api/v1/payment-orders/:payment_id/cancel - cancel an order
%% - POST /api/v1/payment-orders/:payment_id/retry - retry a failed order
-module(cb_payment_orders_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    handle(Method, Req, State).

handle(<<"POST">>, Req, State) ->
    case cowboy_req:binding(payment_id, Req) of
        undefined ->
            initiate_payment(Req, State);
        PaymentId ->
            Path = cowboy_req:path(Req),
            Parts = binary:split(Path, <<"/">>, [global]),
            case Parts of
                [_, <<"api">>, <<"v1">>, <<"payment-orders">>, PaymentId, <<"cancel">>] ->
                    cancel_payment(PaymentId, Req, State);
                [_, <<"api">>, <<"v1">>, <<"payment-orders">>, PaymentId, <<"retry">>] ->
                    retry_payment(PaymentId, Req, State);
                _ ->
                    not_found(Req, State)
            end
    end;

handle(<<"GET">>, Req, State) ->
    case cowboy_req:binding(payment_id, Req) of
        undefined ->
            list_all_payments(Req, State);
        PaymentId ->
            get_payment(PaymentId, Req, State)
    end;

handle(<<"OPTIONS">>, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(405, Headers, <<"{\"error\": \"method_not_allowed\"}">>, Req),
    {ok, Req2, State}.

initiate_payment(Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body) of
        {ok, #{
            <<"idempotency_key">>   := IKey,
            <<"party_id">>          := PartyId,
            <<"source_account_id">> := SourceId,
            <<"dest_account_id">>   := DestId,
            <<"amount">>            := Amount
        }, _} ->
            case cb_payment_orders:initiate(IKey, PartyId, SourceId, DestId, Amount) of
                {ok, Order} ->
                    Resp = order_to_json(Order),
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
    end.

list_all_payments(Req, State) ->
    Orders = cb_payment_orders:list_all(),
    Sorted = lists:sort(fun(A, B) -> A#payment_order.created_at >= B#payment_order.created_at end, Orders),
    Items = [order_to_json(O) || O <- Sorted],
    Resp = #{items => Items},
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req),
    {ok, Req2, State}.

get_payment(PaymentId, Req, State) ->
    case cb_payment_orders:get_payment(PaymentId) of
        {ok, Order} ->
            Resp = order_to_json(Order),
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State};
        {error, Reason} ->
            {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
            Resp = #{error => ErrorAtom, message => Message},
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State}
    end.

cancel_payment(PaymentId, Req, State) ->
    case cb_payment_orders:cancel_payment(PaymentId) of
        {ok, Order} ->
            Resp = order_to_json(Order),
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State};
        {error, Reason} ->
            {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
            Resp = #{error => ErrorAtom, message => Message},
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State}
    end.

retry_payment(PaymentId, Req, State) ->
    case cb_payment_orders:retry_payment(PaymentId) of
        {ok, Order} ->
            Resp = order_to_json(Order),
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State};
        {error, Reason} ->
            {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
            Resp = #{error => ErrorAtom, message => Message},
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State}
    end.

not_found(Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(404, Headers, <<"{\"error\": \"not_found\"}">>, Req),
    {ok, Req2, State}.

order_to_json(Order) ->
    #{
        payment_id        => Order#payment_order.payment_id,
        idempotency_key   => Order#payment_order.idempotency_key,
        party_id          => Order#payment_order.party_id,
        source_account_id => Order#payment_order.source_account_id,
        dest_account_id   => Order#payment_order.dest_account_id,
        amount            => Order#payment_order.amount,
        currency          => Order#payment_order.currency,
        description       => Order#payment_order.description,
        status            => Order#payment_order.status,
        stp_decision      => Order#payment_order.stp_decision,
        failure_reason    => Order#payment_order.failure_reason,
        retry_count       => Order#payment_order.retry_count,
        created_at        => Order#payment_order.created_at,
        updated_at        => Order#payment_order.updated_at
    }.
