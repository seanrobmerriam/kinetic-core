%% @doc CSV Export Handler
%%
%% Handler for `GET /api/v1/export/:resource`
%%
%% Supported resources:
%%   accounts     — All accounts as CSV
%%   transactions — All transactions as CSV
%%   events       — All domain events as CSV
%%
%% For per-account transaction exports, the caller may pass
%% `account_id` as a query parameter.
%%
%% Response: text/csv with content-disposition: attachment
-module(cb_exports_handler).

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    Resource = cowboy_req:binding(resource, Req),
    handle(Method, Resource, Req, State).

handle(<<"GET">>, Resource, Req, State) ->
    Result = case Resource of
        <<"accounts">>     -> cb_exports:export_accounts();
        <<"transactions">> -> export_transactions(Req);
        <<"events">>       -> cb_exports:export_events();
        _                  -> {error, not_found}
    end,
    case Result of
        {ok, CsvData} ->
            Filename = <<Resource/binary, ".csv">>,
            Headers = maps:merge(
                #{
                    <<"content-type">>        => <<"text/csv; charset=utf-8">>,
                    <<"content-disposition">> => <<"attachment; filename=\"", Filename/binary, "\"">>
                },
                cb_cors:headers()
            ),
            Req2 = cowboy_req:reply(200, Headers, CsvData, Req),
            {ok, Req2, State};
        {error, not_found} ->
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(404, Headers, <<"{\"error\": \"not_found\"}">>, Req),
            {ok, Req2, State};
        {error, Reason} ->
            {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
            Resp = #{error => ErrorAtom, message => Message},
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State}
    end;

handle(<<"OPTIONS">>, _Resource, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _Resource, Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(405, Headers, <<"{\"error\": \"method_not_allowed\"}">>, Req),
    {ok, Req2, State}.

export_transactions(Req) ->
    Qs = cowboy_req:parse_qs(Req),
    case proplists:get_value(<<"account_id">>, Qs) of
        undefined -> cb_exports:export_transactions();
        AccountId -> cb_exports:export_account_transactions(AccountId)
    end.
