%% @doc Unified Party Profile Handler
%%
%% Handler for `/api/v1/parties/:party_id/profile`.
%%
%% Returns a composite view of a party including:
%% - Full party record
%% - All accounts owned by the party
%% - The 10 most recent transactions affecting any of those accounts
%%
%% This unified endpoint reduces round-trips for omnichannel clients that
%% need to display a complete customer overview.
%%
%% <h2>REST API Endpoints</h2>
%%
%% <ul>
%%   <li><b>GET /api/v1/parties/:party_id/profile</b> - Composite party view</li>
%%   <li><b>OPTIONS</b> - CORS preflight</li>
%% </ul>
-module(cb_party_profile_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-define(RECENT_TXN_LIMIT, 10).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method  = cowboy_req:method(Req),
    PartyId = cowboy_req:binding(party_id, Req),
    handle(Method, PartyId, Req, State).

handle(<<"GET">>, PartyId, Req, State) ->
    case cb_party:get_party(PartyId) of
        {error, Reason} ->
            {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
            json_reply(Status, #{error => ErrorAtom, message => Message}, Req, State);
        {ok, Party} ->
            Accounts = cb_accounts:list_accounts_for_party(PartyId),
            AccountIds = [A#account.account_id || A <- Accounts],
            RecentTxns = recent_transactions(AccountIds, ?RECENT_TXN_LIMIT),
            Resp = #{
                party    => party_to_json(Party),
                accounts => [account_to_json(A) || A <- Accounts],
                recent_transactions => [txn_to_json(T) || T <- RecentTxns]
            },
            json_reply(200, Resp, Req, State)
    end;

handle(<<"OPTIONS">>, _PartyId, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _PartyId, Req, State) ->
    {_Code405, _Hdrs405, _Body405} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(_Code405, _Hdrs405, _Body405, Req),
    {ok, Req2, State}.

%% Internal helpers

recent_transactions(AccountIds, Limit) ->
    All = lists:flatmap(fun(AccId) ->
        mnesia:dirty_index_read(transaction, AccId, source_account_id) ++
        mnesia:dirty_index_read(transaction, AccId, dest_account_id)
    end, AccountIds),
    Unique = lists:usort(fun(A, B) ->
        A#transaction.txn_id =< B#transaction.txn_id
    end, All),
    Sorted = lists:sort(fun(A, B) ->
        A#transaction.created_at >= B#transaction.created_at
    end, Unique),
    lists:sublist(Sorted, Limit).

party_to_json(P) ->
    #{
        party_id          => P#party.party_id,
        full_name         => P#party.full_name,
        email             => P#party.email,
        status            => P#party.status,
        kyc_status        => P#party.kyc_status,
        onboarding_status => P#party.onboarding_status,
        risk_tier         => P#party.risk_tier,
        created_at        => P#party.created_at,
        updated_at        => P#party.updated_at
    }.

account_to_json(A) ->
    #{
        account_id  => A#account.account_id,
        name        => A#account.name,
        currency    => A#account.currency,
        balance     => A#account.balance,
        status      => A#account.status,
        created_at  => A#account.created_at
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

null_or_val(undefined) -> null;
null_or_val(Val)        -> Val.

json_reply(Status, Body, Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Body), Req),
    {ok, Req2, State}.
