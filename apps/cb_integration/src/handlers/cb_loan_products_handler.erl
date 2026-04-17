-module(cb_loan_products_handler).

-include_lib("cb_loans/include/loan.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    handle(Method, Req, State).

handle(<<"POST">>, Req, State) ->
    Path = cowboy_req:path(Req),
    case cowboy_req:binding(product_id, Req) of
        undefined ->
            create_product(Req, State);
        ProductId when is_binary(ProductId) ->
            case Path of
                <<"/api/v1/loan-products/", _/binary>> ->
                    case binary:split(Path, <<"/">>, [global]) of
                        [_, <<"api">>, <<"v1">>, <<"loan-products">>, ProductId, <<"activate">>] ->
                            set_product_status(ProductId, activate, Req, State);
                        [_, <<"api">>, <<"v1">>, <<"loan-products">>, ProductId, <<"deactivate">>] ->
                            set_product_status(ProductId, deactivate, Req, State);
                        _ ->
                            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                            Req2 = cowboy_req:reply(404, Headers, <<"{\"error\": \"not_found\"}">>, Req),
                            {ok, Req2, State}
                    end;
                _ ->
                    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                    Req2 = cowboy_req:reply(404, Headers, <<"{\"error\": \"not_found\"}">>, Req),
                    {ok, Req2, State}
            end
    end;

handle(<<"GET">>, Req, State) ->
    case cowboy_req:binding(product_id, Req) of
        undefined ->
            Products = cb_loan_products:list_products(),
            Resp = #{
                items => [product_to_json(Product) || Product <- Products]
            },
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State};
        ProductId ->
            case cb_loan_products:get_product(ProductId) of
                {ok, Product} ->
                    Resp = product_to_json(Product),
                    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                    Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req),
                    {ok, Req2, State};
                {error, Reason} ->
                    {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
                    Resp = #{error => ErrorAtom, message => Message},
                    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
                    {ok, Req2, State}
            end
    end;

handle(<<"OPTIONS">>, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(405, Headers, <<"{\"error\": \"method_not_allowed\"}">>, Req),
    {ok, Req2, State}.

has_all_required_fields(Json, Fields) ->
    lists:all(fun(Field) -> maps:is_key(Field, Json) end, Fields).

product_to_json(Product) ->
    #{
        product_id => Product#loan_product.product_id,
        name => Product#loan_product.name,
        description => Product#loan_product.description,
        currency => Product#loan_product.currency,
        min_amount => Product#loan_product.min_amount,
        max_amount => Product#loan_product.max_amount,
        min_term_months => Product#loan_product.min_term_months,
        max_term_months => Product#loan_product.max_term_months,
        interest_rate_bps => Product#loan_product.interest_rate,
        interest_type => Product#loan_product.interest_type,
        status => Product#loan_product.status,
        created_at => Product#loan_product.created_at,
        updated_at => Product#loan_product.updated_at
    }.

create_product(Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body) of
        {ok, Json, _} ->
            RequiredFields = [<<"name">>, <<"description">>, <<"currency">>, <<"min_amount">>, <<"max_amount">>, <<"min_term_months">>, <<"max_term_months">>, <<"interest_rate_bps">>, <<"interest_type">>],
            case has_all_required_fields(Json, RequiredFields) of
                true ->
                    Name = maps:get(<<"name">>, Json),
                    Description = maps:get(<<"description">>, Json),
                    CurrencyBin = maps:get(<<"currency">>, Json),
                    MinAmount = maps:get(<<"min_amount">>, Json),
                    MaxAmount = maps:get(<<"max_amount">>, Json),
                    MinTermMonths = maps:get(<<"min_term_months">>, Json),
                    MaxTermMonths = maps:get(<<"max_term_months">>, Json),
                    InterestRate = maps:get(<<"interest_rate_bps">>, Json),
                    InterestTypeBin = maps:get(<<"interest_type">>, Json),
                    Currency = binary_to_atom(CurrencyBin, utf8),
                    InterestType = binary_to_atom(InterestTypeBin, utf8),
                    case cb_loan_products:create_product(Name, Description, Currency, MinAmount, MaxAmount, MinTermMonths, MaxTermMonths, InterestRate, InterestType) of
                        {ok, ProductId} ->
                            Resp = #{product_id => ProductId},
                            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                            Req3 = cowboy_req:reply(201, Headers, jsone:encode(Resp), Req2),
                            {ok, Req3, State};
                        {error, Reason} ->
                            respond_error(Reason, Req2, State)
                    end;
                false ->
                    respond_error(missing_required_field, Req2, State)
            end;
        _ ->
            respond_error(invalid_json, Req2, State)
    end.

set_product_status(ProductId, activate, Req, State) ->
    case cb_loan_products:activate_product(ProductId) of
        {ok, Product} ->
            Resp = product_to_json(Product),
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State};
        {error, Reason} ->
            respond_error(Reason, Req, State)
    end;
set_product_status(ProductId, deactivate, Req, State) ->
    case cb_loan_products:deactivate_product(ProductId) of
        {ok, Product} ->
            Resp = product_to_json(Product),
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State};
        {error, Reason} ->
            respond_error(Reason, Req, State)
    end.

respond_error(Reason, Req, State) ->
    {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
    Resp = #{error => ErrorAtom, message => Message},
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
    {ok, Req2, State}.
