%% @doc Settlement File Handler
%%
%% Handler for settlement file download.
%%
%% <h2>REST API Endpoints</h2>
%%
%% <ul>
%%   <li><b>GET /api/v1/settlements/files</b> — Download settlement file for date/currency</li>
%%   <li><b>OPTIONS</b> — CORS preflight</li>
%% </ul>
%%
-module(cb_settlement_file_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    handle(Method, Req, State).

handle(<<"GET">>, Req, State) ->
    Qs = cowboy_req:parse_qs(Req),
    DateStr = proplists:get_value(<<"date">>, Qs),
    CurrencyStr = proplists:get_value(<<"currency">>, Qs),

    case {DateStr, CurrencyStr} of
        {undefined, _} ->
            Resp = #{error => missing_parameter, message => <<"date parameter is required">>},
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(400, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State};
        {_, undefined} ->
            Resp = #{error => missing_parameter, message => <<"currency parameter is required">>},
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(400, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State};
        {DateStr, CurrencyStr} ->
            case parse_date(DateStr) of
                {ok, Date} ->
                    Currency = binary_to_atom(list_to_binary(CurrencyStr), utf8),
                    case cb_settlement_file:generate_settlement_file(Date, Currency) of
                        {ok, FileContent, FileName} ->
                            Headers = maps:merge(#{
                                <<"content-type">> => <<"text/csv">>,
                                <<"content-disposition">> => iolist_to_binary([<<"attachment; filename=\"">>, FileName, <<"\"">>])
                            }, cb_cors:headers()),
                            Req2 = cowboy_req:reply(200, Headers, FileContent, Req),
                            {ok, Req2, State};
                        {error, Reason} ->
                            {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
                            Resp = #{error => ErrorAtom, message => Message},
                            RespHeaders = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                            Req2 = cowboy_req:reply(Status, RespHeaders, jsone:encode(Resp), Req),
                            {ok, Req2, State}
                    end;
                {error, _} ->
                    Resp = #{error => invalid_date, message => <<"date must be in YYYY-MM-DD format">>},
                    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                    Req2 = cowboy_req:reply(400, Headers, jsone:encode(Resp), Req),
                    {ok, Req2, State}
            end
    end;

handle(<<"OPTIONS">>, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, Req, State) ->
    {_Code405, _Hdrs405, _Body405} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(_Code405, _Hdrs405, _Body405, Req),
    {ok, Req2, State}.

-spec parse_date(binary() | string()) -> {ok, calendar:date()} | {error, invalid_date}.
parse_date(DateStr) when is_binary(DateStr) ->
    parse_date(binary_to_list(DateStr));
parse_date(DateStr) ->
    case string:split(DateStr, "-", all) of
        [YStr, MSc, DStr] ->
            try
                Y = list_to_integer(YStr),
                M = list_to_integer(MSc),
                D = list_to_integer(DStr),
                case calendar:valid_date(Y, M, D) of
                    true -> {ok, {Y, M, D}};
                    false -> {error, invalid_date}
                end
            catch
                _:_ -> {error, invalid_date}
            end;
        _ ->
            {error, invalid_date}
    end.