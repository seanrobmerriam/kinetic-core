-module(cb_savings_products_list_handler).

-include_lib("cb_savings_products/include/savings_product.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    handle(Method, Req, State).

handle(<<"GET">>, Req, State) ->
    case cb_savings_products:list_products() of
        {ok, Products} ->
            Resp = #{
                items => [product_to_json(P) || P <- Products]
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

handle(<<"OPTIONS">>, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, Req, State) ->
    {_Code405, _Hdrs405, _Body405} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(_Code405, _Hdrs405, _Body405, Req),
    {ok, Req2, State}.

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
        created_at => Product#savings_product.created_at,
        updated_at => Product#savings_product.updated_at
    }.
