%% @doc Account Balance Snapshots HTTP Handler
%%
%% Endpoints:
%%   GET  /api/v1/accounts/:account_id/snapshots  - list historical snapshots
%%   POST /api/v1/accounts/:account_id/snapshots  - capture a new snapshot
%%
%% Balance snapshots are point-in-time records of an account's balance.
%% They support archiving and historical reporting without re-scanning
%% the full ledger entry history.
%%
%% GET query parameters:
%%   - page      : 1-indexed (default: 1)
%%   - page_size : 1-100 (default: 20)
-module(cb_account_snapshots_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method    = cowboy_req:method(Req),
    AccountId = cowboy_req:binding(account_id, Req),
    handle(Method, AccountId, Req, State).

handle(<<"GET">>, AccountId, Req, State) ->
    Qs       = cowboy_req:parse_qs(Req),
    Page     = parse_int(proplists:get_value(<<"page">>, Qs), 1),
    PageSize = parse_int(proplists:get_value(<<"page_size">>, Qs), 20),
    case cb_ledger:get_balance_snapshots(AccountId, Page, PageSize) of
        {ok, #{items := Snapshots} = Result} ->
            Items = [snapshot_to_json(S) || S <- Snapshots],
            Resp  = Result#{items => Items},
            reply(200, Resp, Req, State);
        {error, Reason} ->
            error_reply(Reason, Req, State)
    end;

handle(<<"POST">>, AccountId, Req, State) ->
    case cb_ledger:create_balance_snapshot(AccountId) of
        {ok, Snapshot} ->
            reply(201, snapshot_to_json(Snapshot), Req, State);
        {error, Reason} ->
            error_reply(Reason, Req, State)
    end;

handle(<<"OPTIONS">>, _AccountId, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _AccountId, Req, State) ->
    reply(405, #{error => method_not_allowed, message => <<"Method not allowed">>}, Req, State).

%% =============================================================================
%% Internal helpers
%% =============================================================================

parse_int(undefined, Default) -> Default;
parse_int(Bin, Default) ->
    try binary_to_integer(Bin)
    catch _:_ -> Default
    end.

reply(Status, Body, Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Body), Req),
    {ok, Req2, State}.

error_reply(Reason, Req, State) ->
    {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
    reply(Status, #{error => ErrorAtom, message => Message}, Req, State).

snapshot_to_json(S) ->
    #{
        snapshot_id => S#balance_snapshot.snapshot_id,
        account_id  => S#balance_snapshot.account_id,
        balance     => S#balance_snapshot.balance,
        currency    => S#balance_snapshot.currency,
        snapshot_at => S#balance_snapshot.snapshot_at
    }.
