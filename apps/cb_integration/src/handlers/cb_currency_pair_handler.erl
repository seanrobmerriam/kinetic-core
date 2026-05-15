%% @doc Currency Pair Handler
%%
%% Handler for `POST|GET /api/v1/currency-pairs` and `GET|PATCH /api/v1/currency-pairs/:pair_id`.
%%
%% <h2>REST API Endpoints</h2>
%%
%% <ul>
%%   <li><b>POST /api/v1/currency-pairs</b> - Create a new currency pair</li>
%%   <li><b>GET /api/v1/currency-pairs</b> - List all currency pairs</li>
%%   <li><b>GET /api/v1/currency-pairs/:pair_id</b> - Get a specific pair (e.g., USD/EUR)</li>
%%   <li><b>PATCH /api/v1/currency-pairs/:pair_id</b> - Update spread or settlement currency</li>
%%   <li><b>OPTIONS</b> - CORS preflight</li>
%% </ul>
%%
-module(cb_currency_pair_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    PairId = cowboy_req:binding(pair_id, Req),
    handle(Method, PairId, Req, State).

%% POST /api/v1/currency-pairs — create a new pair
handle(<<"POST">>, undefined, Req, State) ->
    case jsone:decode(Req) of
        {ok, Body, Req1} ->
            FromCurrency = binary_to_atom(maps:get(<<"from_currency">>, Body), utf8),
            ToCurrency = binary_to_atom(maps:get(<<"to_currency">>, Body), utf8),
            SpreadMillionths = maps:get(<<"spread_millionths">>, Body),
            SettlementCurrency = binary_to_atom(maps:get(<<"settlement_currency">>, Body), utf8),
            case cb_currency_pair:create_pair(FromCurrency, ToCurrency, SpreadMillionths, SettlementCurrency) of
                {ok, Pair} ->
                    Resp = pair_to_json(Pair),
                    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                    Req2 = cowboy_req:reply(201, Headers, jsone:encode(Resp), Req1),
                    {ok, Req2, State};
                {error, Reason} ->
                    {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
                    Resp = #{error => ErrorAtom, message => Message},
                    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req1),
                    {ok, Req2, State}
            end;
        {error, _} ->
            {Code, Hdrs, Body} = cb_http_errors:to_response_with_metrics(bad_request),
            Req2 = cowboy_req:reply(Code, Hdrs, Body, Req),
            {ok, Req2, State}
    end;

%% GET /api/v1/currency-pairs — list all pairs
handle(<<"GET">>, undefined, Req, State) ->
    Pairs = cb_currency_pair:list_pairs(),
    Resp = [pair_to_json(P) || P <- Pairs],
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req),
    {ok, Req2, State};

%% GET /api/v1/currency-pairs/:pair_id — get a specific pair
handle(<<"GET">>, PairId, Req, State) ->
    case cb_currency_pair:get_pair(PairId) of
        {ok, Pair} ->
            Resp = pair_to_json(Pair),
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

%% PATCH /api/v1/currency-pairs/:pair_id — update spread/settlement
handle(<<"PATCH">>, PairId, Req, State) ->
    case jsone:decode(Req) of
        {ok, Body, Req1} ->
            Updates = #{
                spread_millionths => maps:get(<<"spread_millionths">>, Body, undefined),
                settlement_currency => case maps:get(<<"settlement_currency">>, Body, undefined) of
                    undefined -> undefined;
                    SC -> binary_to_atom(SC, utf8)
                end
            },
            UpdatesClean = maps:filter(fun(_, V) -> V =/= undefined end, Updates),
            case cb_currency_pair:update_pair(PairId, UpdatesClean) of
                {ok, Pair} ->
                    Resp = pair_to_json(Pair),
                    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                    Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req1),
                    {ok, Req2, State};
                {error, Reason} ->
                    {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
                    Resp = #{error => ErrorAtom, message => Message},
                    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req1),
                    {ok, Req2, State}
            end;
        {error, _} ->
            {Code, Hdrs, Body} = cb_http_errors:to_response_with_metrics(bad_request),
            Req2 = cowboy_req:reply(Code, Hdrs, Body, Req),
            {ok, Req2, State}
    end;

handle(<<"OPTIONS">>, _PairId, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _PairId, Req, State) ->
    {_Code405, _Hdrs405, _Body405} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(_Code405, _Hdrs405, _Body405, Req),
    {ok, Req2, State}.

pair_to_json(Pair) ->
    #{
        pair_id => Pair#currency_pair.pair_id,
        from_currency => atom_to_binary(Pair#currency_pair.from_currency, utf8),
        to_currency => atom_to_binary(Pair#currency_pair.to_currency, utf8),
        spread_millionths => Pair#currency_pair.spread_millionths,
        settlement_currency => atom_to_binary(Pair#currency_pair.settlement_currency, utf8),
        created_at => Pair#currency_pair.created_at,
        updated_at => Pair#currency_pair.updated_at
    }.