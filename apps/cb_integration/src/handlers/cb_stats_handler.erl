%% @doc System Statistics Handler
%%
%% Handler for the `/api/v1/stats` endpoint which provides system-wide statistics.
%%
%% <h2>Purpose</h2>
%%
%% Provides aggregate statistics about the banking system including:
%% <ul>
%%   <li>Total number of parties (customers)</li>
%%   <li>Total number of accounts</li>
%%   <li>Total balance across all accounts</li>
%%   <li>Account status breakdown (active, frozen, closed)</li>
%% </ul>
%%
%% This endpoint is useful for:
%% <ul>
%%   <li>Dashboard displays</li>
%%   <li>Monitoring and reporting</li>
%%   <li>Admin interfaces</li>
%% </ul>
%%
%% <h2>REST API Endpoints</h2>
%%
%% <ul>
%%   <li><b>GET /api/v1/stats</b> - Get system statistics</li>
%%   <li><b>OPTIONS /api/v1/stats</b> - CORS preflight</li>
%% </ul>
%%
%% <h2>Response Format</h2>
%%
%% <pre>
%% {
%%   "total_parties": 100,
%%   "total_accounts": 250,
%%   "total_balance": 50000000,
%%   "active_accounts": 200,
%%   "frozen_accounts": 30,
%%   "closed_accounts": 20
%% }
%% </pre>
%%
%% Note: All monetary values are in minor units (cents/pence).
-module(cb_stats_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    handle(Method, Req, State).

handle(<<"GET">>, Req, State) ->
    case get_stats() of
        {ok, Stats} ->
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(200, Headers, jsone:encode(Stats), Req),
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

get_stats() ->
    F = fun() ->
        AllParties = mnesia:select(party, [{'_', [], ['$_']}]),
        AllAccounts = mnesia:select(account, [{'_', [], ['$_']}]),
        
        TotalParties = length(AllParties),
        TotalAccounts = length(AllAccounts),
        TotalBalance = lists:foldl(
            fun(Account, Acc) -> Acc + Account#account.balance end,
            0,
            AllAccounts
        ),
        
        ActiveAccounts = length([A || A <- AllAccounts, A#account.status =:= active]),
        FrozenAccounts = length([A || A <- AllAccounts, A#account.status =:= frozen]),
        ClosedAccounts = length([A || A <- AllAccounts, A#account.status =:= closed]),
        
        {ok, #{
            total_parties => TotalParties,
            total_accounts => TotalAccounts,
            total_balance => TotalBalance,
            active_accounts => ActiveAccounts,
            frozen_accounts => FrozenAccounts,
            closed_accounts => ClosedAccounts
        }}
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.
