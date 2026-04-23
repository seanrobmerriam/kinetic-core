%% @doc Single Account Handler
%%
%% Handler for the `/api/v1/accounts/:account_id` endpoint for individual account operations.
%%
%% <h2>REST API Endpoints</h2>
%%
%% <ul>
%%   <li><b>GET /api/v1/accounts/:account_id</b> - Get account details</li>
%%   <li><b>OPTIONS /api/v1/accounts/:account_id</b> - CORS preflight</li>
%% </ul>
%%
%% <h2>GET - Get Account</h2>
%%
%% Retrieves detailed information about a specific account by its ID.
%% The account_id is extracted from the URL path binding.
%%
%% Response includes:
%% <ul>
%%   <li>account_id - Unique identifier</li>
%%   <li>party_id - Owner party UUID</li>
%%   <li>name - Account name</li>
%%   <li>currency - ISO 4217 currency code</li>
%%   <li>balance - Current balance in minor units</li>
%%   <li>status - Account status (active, frozen, closed)</li>
%%   <li>created_at - Creation timestamp</li>
%%   <li>updated_at - Last modification timestamp</li>
%% </ul>
%%
%% @see cb_accounts
%% @see cb_accounts_handler
-module(cb_account_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    AccountId = cowboy_req:binding(account_id, Req),
    handle(Method, AccountId, Req, State).

handle(<<"GET">>, AccountId, Req, State) ->
    case cb_accounts:get_account(AccountId) of
        {ok, Account} ->
            Resp = account_to_json(Account),
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

handle(<<"OPTIONS">>, _AccountId, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _AccountId, Req, State) ->
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
