%% @doc Composite Account Summary Handler
%%
%% Handler for `/api/v1/accounts/:account_id/summary`.
%%
%% Returns a composite view of an account including:
%% - Full account record
%% - The 10 most recent transactions affecting this account
%% - All active holds on this account
%%
%% This unified endpoint reduces round-trips for clients that need a
%% complete account overview in a single request.
%%
%% <h2>REST API Endpoints</h2>
%%
%% <ul>
%%   <li><b>GET /api/v1/accounts/:account_id/summary</b> - Composite account view</li>
%%   <li><b>OPTIONS</b> - CORS preflight</li>
%% </ul>
-module(cb_account_summary_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-define(RECENT_TXN_LIMIT, 10).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method    = cowboy_req:method(Req),
    AccountId = cowboy_req:binding(account_id, Req),
    handle(Method, AccountId, Req, State).

handle(<<"GET">>, AccountId, Req, State) ->
    case cb_accounts:get_account(AccountId) of
        {error, Reason} ->
            {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
            json_reply(Status, #{error => ErrorAtom, message => Message}, Req, State);
        {ok, Account} ->
            RecentTxns = recent_transactions(AccountId, ?RECENT_TXN_LIMIT),
            ActiveHolds = case cb_account_holds:list_holds(AccountId) of
                {ok, Holds} -> [H || H <- Holds, H#account_hold.status =:= active];
                {error, _}  -> []
            end,
            Resp = #{
                account             => account_to_json(Account),
                recent_transactions => [txn_to_json(T) || T <- RecentTxns],
                active_holds        => [hold_to_json(H) || H <- ActiveHolds]
            },
            json_reply(200, Resp, Req, State)
    end;

handle(<<"OPTIONS">>, _AccountId, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _AccountId, Req, State) ->
    {_Code405, _Hdrs405, _Body405} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(_Code405, _Hdrs405, _Body405, Req),
    {ok, Req2, State}.

%% Internal helpers

recent_transactions(AccountId, Limit) ->
    All = mnesia:dirty_index_read(transaction, AccountId, source_account_id) ++
          mnesia:dirty_index_read(transaction, AccountId, dest_account_id),
    Unique = lists:usort(fun(A, B) ->
        A#transaction.txn_id =< B#transaction.txn_id
    end, All),
    Sorted = lists:sort(fun(A, B) ->
        A#transaction.created_at >= B#transaction.created_at
    end, Unique),
    lists:sublist(Sorted, Limit).

account_to_json(A) ->
    #{
        account_id  => A#account.account_id,
        party_id    => A#account.party_id,
        name        => A#account.name,
        currency    => A#account.currency,
        balance     => A#account.balance,
        status      => A#account.status,
        created_at  => A#account.created_at,
        updated_at  => A#account.updated_at
    }.

txn_to_json(T) ->
    #{
        txn_id     => T#transaction.txn_id,
        txn_type   => T#transaction.txn_type,
        status     => T#transaction.status,
        amount     => T#transaction.amount,
        currency   => T#transaction.currency,
        channel    => null_or_val(T#transaction.channel),
        created_at => T#transaction.created_at
    }.

hold_to_json(H) ->
    #{
        hold_id     => H#account_hold.hold_id,
        account_id  => H#account_hold.account_id,
        amount      => H#account_hold.amount,
        reason      => H#account_hold.reason,
        status      => H#account_hold.status,
        placed_at   => H#account_hold.placed_at,
        released_at => null_or_val(H#account_hold.released_at),
        expires_at  => null_or_val(H#account_hold.expires_at)
    }.

null_or_val(undefined) -> null;
null_or_val(Val)        -> Val.

json_reply(Status, Body, Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Body), Req),
    {ok, Req2, State}.
