%% @doc Account Balance Handler
%%
%% Handler for the `/api/v1/accounts/:account_id/balance` endpoint.
%%
%% <h2>Purpose</h2>
%%
%% Returns the current balance of a specific account. This is a dedicated endpoint
%% for balance queries, separate from the main account details endpoint, allowing
%% for optimized balance lookups without fetching full account data.
%%
%% <h2>REST API Endpoints</h2>
%%
%% <ul>
%%   <li><b>GET /api/v1/accounts/:account_id/balance</b> - Get account balance</li>
%%   <li><b>OPTIONS /api/v1/accounts/:account_id/balance</b> - CORS preflight</li>
%% </ul>
%%
%% <h2>Response Format</h2>
%%
%% Returns a JSON object with the balance information:
%% <pre>
%% {
%%   "account_id": "uuid",
%%   "balance": 100000,
%%   "available_balance": 100000,
%%   "currency": "USD"
%% }
%% </pre>
%%
%% All amounts are in minor units (cents, pence, etc.).
%%
%% @see cb_accounts
-module(cb_account_balance_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    AccountId = cowboy_req:binding(account_id, Req),
    handle(Method, AccountId, Req, State).

handle(<<"GET">>, AccountId, Req, State) ->
    case cb_accounts:get_balance(AccountId) of
        {ok, Result} ->
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(200, Headers, jsone:encode(Result), Req),
            {ok, Req2, State};
        {error, Reason} ->
            {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
            Resp = #{error => ErrorAtom, message => Message},
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State}
    end;

handle(<<"OPTIONS">>, _AccountId, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _AccountId, Req, State) ->
    {_Code405, _Hdrs405, _Body405} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(_Code405, _Hdrs405, _Body405, Req),
    {ok, Req2, State}.
