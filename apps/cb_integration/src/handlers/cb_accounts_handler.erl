%% @doc Accounts List Handler
%%
%% Handler for the `/api/v1/accounts` endpoint which provides account management.
%%
%% <h2>REST API Endpoints</h2>
%%
%% <ul>
%%   <li><b>GET /api/v1/accounts</b> - List all accounts with pagination</li>
%%   <li><b>POST /api/v1/accounts</b> - Create a new account</li>
%%   <li><b>OPTIONS /api/v1/accounts</b> - CORS preflight</li>
%% </ul>
%%
%% <h2>GET - List Accounts</h2>
%%
%% Returns a paginated list of accounts. Supports query parameters:
%% <ul>
%%   <li><code>page</code> - Page number (default: 1)</li>
%%   <li><code>page_size</code> - Items per page (default: 20)</li>
%% </ul>
%%
%% Response format:
%% <pre>
%% {
%%   "items": [...],
%%   "total": 100,
%%   "page": 1,
%%   "page_size": 20
%% }
%% </pre>
%%
%% <h2>POST - Create Account</h2>
%%
%% Creates a new bank account. Required fields:
%% <ul>
%%   <li><code>party_id</code> - UUID of the owner party</li>
%%   <li><code>currency</code> - ISO 4217 currency code (e.g., "USD")</li>
%%   <li><code>name</code> - Account name</li>
%% </ul>
%%
%% On success, returns 201 Created with the new account details.
%%
%% @see cb_accounts
%% @see cb_account_handler
-module(cb_accounts_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    handle(Method, Req, State).

handle(<<"GET">>, Req, State) ->
    Qs = cowboy_req:parse_qs(Req),
    Page = binary_to_integer(proplists:get_value(<<"page">>, Qs, <<"1">>)),
    PageSize = binary_to_integer(proplists:get_value(<<"page_size">>, Qs, <<"20">>)),
    case cb_accounts:list_accounts(Page, PageSize) of
        {ok, Result} ->
            Resp = #{
                items => [account_to_json(A) || A <- maps:get(items, Result)],
                total => maps:get(total, Result),
                page => maps:get(page, Result),
                page_size => maps:get(page_size, Result)
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

handle(<<"POST">>, Req, State) ->
    %% Create account
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body) of
        {ok, #{<<"party_id">> := PartyId, <<"currency">> := CurrencyBin, <<"name">> := Name}, _} ->
            Currency = binary_to_atom(CurrencyBin, utf8),
            case cb_accounts:create_account(PartyId, Name, Currency) of
                {ok, Account} ->
                    Resp = account_to_json(Account),
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
    end;

handle(<<"OPTIONS">>, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, Req, State) ->
    {_Code405, _Hdrs405, _Body405} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(_Code405, _Hdrs405, _Body405, Req),
    {ok, Req2, State}.

account_to_json(Account) ->
    #{
        account_id => Account#account.account_id,
        party_id => Account#account.party_id,
        name => Account#account.name,
        currency => Account#account.currency,
        balance => Account#account.balance,
        status => Account#account.status,
        created_at => Account#account.created_at,
        updated_at => Account#account.updated_at
    }.
