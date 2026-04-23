%% @doc General Ledger Report HTTP Handler
%%
%% Endpoint:
%%   GET /api/v1/ledger/general-ledger
%%
%% Returns a paginated view of all ledger entries, optionally filtered.
%% This is the primary endpoint for general ledger reporting and audit.
%%
%% Query parameters (all optional):
%%   - account_id  : restrict to entries for one account
%%   - entry_type  : debit | credit
%%   - currency    : ISO 4217 code, e.g. USD
%%   - from_ms     : lower bound on posted_at (milliseconds epoch, inclusive)
%%   - to_ms       : upper bound on posted_at (milliseconds epoch, inclusive)
%%   - page        : 1-indexed page number (default: 1)
%%   - page_size   : entries per page, 1-100 (default: 20)
-module(cb_ledger_gl_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    handle(Method, Req, State).

handle(<<"GET">>, Req, State) ->
    Qs       = cowboy_req:parse_qs(Req),
    Page     = parse_int(proplists:get_value(<<"page">>, Qs), 1),
    PageSize = parse_int(proplists:get_value(<<"page_size">>, Qs), 20),
    Filters  = build_filters(Qs),
    case cb_ledger:get_general_ledger_entries(Filters, Page, PageSize, 500) of
        {ok, #{items := Entries} = Result} ->
            Items  = [entry_to_json(E) || E <- Entries],
            Resp   = Result#{items => Items},
            reply(200, Resp, Req, State);
        {error, Reason} ->
            error_reply(Reason, Req, State)
    end;

handle(<<"OPTIONS">>, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, Req, State) ->
    reply(405, #{error => method_not_allowed, message => <<"Method not allowed">>}, Req, State).

%% =============================================================================
%% Internal helpers
%% =============================================================================

build_filters(Qs) ->
    Base = #{},
    F0 = case proplists:get_value(<<"account_id">>, Qs) of
        undefined -> Base;
        AccId     -> Base#{account_id => AccId}
    end,
    F1 = case proplists:get_value(<<"entry_type">>, Qs) of
        undefined -> F0;
        ETBin     -> F0#{entry_type => binary_to_existing_atom(ETBin, utf8)}
    end,
    F2 = case proplists:get_value(<<"currency">>, Qs) of
        undefined -> F1;
        CBin      -> F1#{currency => binary_to_existing_atom(CBin, utf8)}
    end,
    F3 = case proplists:get_value(<<"from_ms">>, Qs) of
        undefined -> F2;
        FromBin   -> F2#{from_ms => binary_to_integer(FromBin)}
    end,
    case proplists:get_value(<<"to_ms">>, Qs) of
        undefined -> F3;
        ToBin     -> F3#{to_ms => binary_to_integer(ToBin)}
    end.

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

entry_to_json(E) ->
    #{
        entry_id    => E#ledger_entry.entry_id,
        txn_id      => E#ledger_entry.txn_id,
        account_id  => E#ledger_entry.account_id,
        entry_type  => E#ledger_entry.entry_type,
        amount      => E#ledger_entry.amount,
        currency    => E#ledger_entry.currency,
        description => E#ledger_entry.description,
        posted_at   => E#ledger_entry.posted_at
    }.
