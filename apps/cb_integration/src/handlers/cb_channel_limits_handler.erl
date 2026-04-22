%% @doc Channel Transaction Limits Handler
%%
%% Handler for `/api/v1/channel-limits/:channel` endpoints.
%%
%% <h2>REST API Endpoints</h2>
%%
%% <ul>
%%   <li><b>GET /api/v1/channel-limits/:channel</b> - Get limits for a channel</li>
%%   <li><b>PUT /api/v1/channel-limits/:channel</b> - Set limits for a channel (admin)</li>
%%   <li><b>GET /api/v1/channel-limits</b> - List all channel limits (admin)</li>
%%   <li><b>OPTIONS</b> - CORS preflight</li>
%% </ul>
%%
%% <h2>PUT body</h2>
%%
%% <pre>
%% {
%%   "currency":      "USD",
%%   "daily_limit":   500000,
%%   "per_txn_limit": 100000
%% }
%% </pre>
%%
%% Limit values are in minor units. Use 0 for unlimited.
-module(cb_channel_limits_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method   = cowboy_req:method(Req),
    ChannelB = cowboy_req:binding(channel, Req),
    handle(Method, ChannelB, Req, State).

handle(<<"GET">>, undefined, Req, State) ->
    Limits = cb_channel_limits:list_all(),
    Resp = [limit_to_json(L) || L <- Limits],
    json_reply(200, Resp, Req, State);

handle(<<"GET">>, ChannelBin, Req, State) ->
    case parse_channel(ChannelBin) of
        {ok, Channel} ->
            Qs        = cowboy_req:parse_qs(Req),
            CurrBin   = proplists:get_value(<<"currency">>, Qs, <<"USD">>),
            case parse_currency(CurrBin) of
                {ok, Currency} ->
                    {ok, Limit} = cb_channel_limits:get_limits(Channel, Currency),
                    json_reply(200, limit_to_json(Limit), Req, State);
                {error, _} ->
                    error_reply(invalid_currency, Req, State)
            end;
        {error, _} ->
            error_reply(invalid_channel, Req, State)
    end;

handle(<<"PUT">>, ChannelBin, Req, State) ->
    case parse_channel(ChannelBin) of
        {ok, Channel} ->
            {ok, Body, Req2} = cowboy_req:read_body(Req),
            case jsone:try_decode(Body) of
                {ok, Decoded, _} ->
                    CurrBin   = maps:get(<<"currency">>, Decoded, <<"USD">>),
                    Daily     = maps:get(<<"daily_limit">>,   Decoded, 0),
                    PerTxn    = maps:get(<<"per_txn_limit">>, Decoded, 0),
                    case parse_currency(CurrBin) of
                        {ok, Currency} ->
                            case cb_channel_limits:set_limits(Channel, Currency, Daily, PerTxn) of
                                {ok, Limit} ->
                                    json_reply(200, limit_to_json(Limit), Req2, State);
                                {error, Reason} ->
                                    error_reply(Reason, Req2, State)
                            end;
                        {error, _} ->
                            error_reply(invalid_currency, Req2, State)
                    end;
                _ ->
                    error_reply(missing_required_field, Req, State)
            end;
        {error, _} ->
            error_reply(invalid_channel, Req, State)
    end;

handle(<<"OPTIONS">>, _Channel, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _Channel, Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(405, Headers, <<"{\"error\":\"method_not_allowed\"}">>, Req),
    {ok, Req2, State}.

%% Internal helpers

limit_to_json(#channel_limit{} = L) ->
    {Channel, Currency} = L#channel_limit.limit_key,
    #{
        channel_type  => Channel,
        currency      => Currency,
        daily_limit   => L#channel_limit.daily_limit,
        per_txn_limit => L#channel_limit.per_txn_limit,
        updated_at    => L#channel_limit.updated_at
    }.

json_reply(Status, Body, Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Body), Req),
    {ok, Req2, State}.

error_reply(Reason, Req, State) ->
    {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
    Resp = #{error => ErrorAtom, message => Message},
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
    {ok, Req2, State}.

parse_channel(<<"web">>)    -> {ok, web};
parse_channel(<<"mobile">>) -> {ok, mobile};
parse_channel(<<"branch">>) -> {ok, branch};
parse_channel(<<"atm">>)    -> {ok, atm};
parse_channel(_)            -> {error, invalid_channel}.

parse_currency(<<"USD">>) -> {ok, 'USD'};
parse_currency(<<"EUR">>) -> {ok, 'EUR'};
parse_currency(<<"GBP">>) -> {ok, 'GBP'};
parse_currency(<<"JPY">>) -> {ok, 'JPY'};
parse_currency(<<"CHF">>) -> {ok, 'CHF'};
parse_currency(<<"AUD">>) -> {ok, 'AUD'};
parse_currency(<<"CAD">>) -> {ok, 'CAD'};
parse_currency(<<"SGD">>) -> {ok, 'SGD'};
parse_currency(<<"HKD">>) -> {ok, 'HKD'};
parse_currency(<<"NZD">>) -> {ok, 'NZD'};
parse_currency(_)         -> {error, invalid_currency}.
