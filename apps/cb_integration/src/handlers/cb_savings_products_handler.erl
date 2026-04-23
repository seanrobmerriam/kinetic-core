-module(cb_savings_products_handler).

-include_lib("cb_savings_products/include/savings_product.hrl").

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
                <<"/api/v1/savings-products/", _/binary>> ->
                    case binary:split(Path, <<"/">>, [global]) of
                        [_, <<"api">>, <<"v1">>, <<"savings-products">>, ProductId, <<"activate">>] ->
                            set_product_status(ProductId, activate, Req, State);
                        [_, <<"api">>, <<"v1">>, <<"savings-products">>, ProductId, <<"deactivate">>] ->
                            set_product_status(ProductId, deactivate, Req, State);
                        [_, <<"api">>, <<"v1">>, <<"savings-products">>, ProductId, <<"launch">>] ->
                            set_product_status(ProductId, launch, Req, State);
                        [_, <<"api">>, <<"v1">>, <<"savings-products">>, ProductId, <<"sunset">>] ->
                            set_product_status(ProductId, sunset, Req, State);
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
            case cb_savings_products:list_products() of
                {ok, Products} ->
                    Resp = #{items => [product_to_json(Product) || Product <- Products]},
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
        ProductId ->
            case cb_savings_products:get_product(ProductId) of
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

handle(<<"PATCH">>, Req, State) ->
    case cowboy_req:binding(product_id, Req) of
        undefined ->
            respond_error(not_found, Req, State);
        ProductId ->
            {ok, Body, Req2} = cowboy_req:read_body(Req),
            case jsone:try_decode(Body) of
                {ok, Json, _} when is_map(Json) ->
                    Updates = decode_update_fields(Json),
                    case cb_savings_products:update_product(ProductId, Updates) of
                        {ok, Product} ->
                            Resp = product_to_json(Product),
                            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                            Req3 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req2),
                            {ok, Req3, State};
                        {error, Reason} ->
                            respond_error(Reason, Req2, State)
                    end;
                _ ->
                    respond_error(invalid_json, Req2, State)
            end
    end;

handle(<<"OPTIONS">>, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, Req, State) ->
    {_Code405, _Hdrs405, _Body405} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(_Code405, _Hdrs405, _Body405, Req),
    {ok, Req2, State}.

has_all_required_fields(Json, Fields) ->
    lists:all(fun(Field) -> maps:is_key(Field, Json) end, Fields).

product_to_json(Product) ->
    #{
        product_id => Product#savings_product.product_id,
        name => Product#savings_product.name,
        description => Product#savings_product.description,
        currency => Product#savings_product.currency,
        interest_rate_bps => Product#savings_product.interest_rate,
        interest_type => Product#savings_product.interest_type,
        compounding_period => Product#savings_product.compounding_period,
        minimum_balance => Product#savings_product.minimum_balance,
        status => Product#savings_product.status,
        version => Product#savings_product.version,
        created_at => Product#savings_product.created_at,
        updated_at => Product#savings_product.updated_at
    }.

create_product(Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body) of
        {ok, Json, _} ->
            RequiredFields = [<<"name">>, <<"description">>, <<"currency">>, <<"interest_rate_bps">>, <<"interest_type">>, <<"compounding_period">>, <<"minimum_balance">>],
            case has_all_required_fields(Json, RequiredFields) of
                true ->
                    Name = maps:get(<<"name">>, Json),
                    Description = maps:get(<<"description">>, Json),
                    CurrencyBin = maps:get(<<"currency">>, Json),
                    InterestRate = maps:get(<<"interest_rate_bps">>, Json),
                    InterestTypeBin = maps:get(<<"interest_type">>, Json),
                    CompoundingPeriodBin = maps:get(<<"compounding_period">>, Json),
                    MinimumBalance = maps:get(<<"minimum_balance">>, Json),
                    Currency = binary_to_atom(CurrencyBin, utf8),
                    InterestType = binary_to_atom(InterestTypeBin, utf8),
                    CompoundingPeriod = binary_to_atom(CompoundingPeriodBin, utf8),
                    Draft = maps:get(<<"draft">>, Json, false),
                    CreateFn = case Draft of
                        true  -> fun cb_savings_products:create_draft_product/7;
                        false -> fun cb_savings_products:create_product/7
                    end,
                    case CreateFn(Name, Description, Currency, InterestRate, InterestType, CompoundingPeriod, MinimumBalance) of
                        {ok, Product} ->
                            Resp = product_to_json(Product),
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
    case cb_savings_products:activate_product(ProductId) of
        {ok, Product} ->
            Resp = product_to_json(Product),
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State};
        {error, Reason} ->
            respond_error(Reason, Req, State)
    end;
set_product_status(ProductId, deactivate, Req, State) ->
    case cb_savings_products:deactivate_product(ProductId) of
        {ok, Product} ->
            Resp = product_to_json(Product),
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State};
        {error, Reason} ->
            respond_error(Reason, Req, State)
    end;
set_product_status(ProductId, launch, Req, State) ->
    case cb_savings_products:launch_product(ProductId) of
        {ok, Product} ->
            Resp = product_to_json(Product),
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State};
        {error, Reason} ->
            respond_error(Reason, Req, State)
    end;
set_product_status(ProductId, sunset, Req, State) ->
    case cb_savings_products:sunset_product(ProductId) of
        {ok, Product} ->
            Resp = product_to_json(Product),
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State};
        {error, Reason} ->
            respond_error(Reason, Req, State)
    end.

decode_update_fields(Json) ->
    Keys = [
        {name,               <<"name">>},
        {description,        <<"description">>},
        {interest_rate,      <<"interest_rate_bps">>},
        {interest_type,      <<"interest_type">>},
        {compounding_period, <<"compounding_period">>},
        {minimum_balance,    <<"minimum_balance">>}
    ],
    lists:foldl(fun({AtomKey, BinKey}, Acc) ->
        case maps:get(BinKey, Json, undefined) of
            undefined -> Acc;
            Value     -> Acc#{AtomKey => Value}
        end
    end, #{}, Keys).

respond_error(Reason, Req, State) ->
    {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
    Resp = #{error => ErrorAtom, message => Message},
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
    {ok, Req2, State}.
