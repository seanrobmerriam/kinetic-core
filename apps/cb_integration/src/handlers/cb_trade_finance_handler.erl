%% @doc HTTP handler for Trade Finance API (TASK-063)
%%
%% Routes:
%%   POST   /api/v1/trade/instruments                   — issue_instrument
%%   GET    /api/v1/trade/instruments                   — list_instruments (query: account_id)
%%   GET    /api/v1/trade/instruments/:id               — get_instrument
%%   POST   /api/v1/trade/instruments/:id/amend         — amend_instrument
%%   POST   /api/v1/trade/instruments/:id/settle        — settle_instrument
%%   POST   /api/v1/trade/instruments/:id/expire        — expire_instrument
%%   POST   /api/v1/trade/instruments/:id/cancel        — cancel_instrument
%%   POST   /api/v1/trade/instruments/:id/documents     — add_document
%%   GET    /api/v1/trade/instruments/:id/documents     — list_documents
%%   POST   /api/v1/trade/documents/:id/review          — review_document
-module(cb_trade_finance_handler).

-include("../../cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

init(Req0, State) ->
    Method   = cowboy_req:method(Req0),
    PathInfo = cowboy_req:path_info(Req0),
    {ok, Req} = handle(Method, PathInfo, Req0),
    {ok, Req, State}.

handle(<<"POST">>, [], Req0) ->
    handle_issue(Req0);
handle(<<"GET">>, [], Req0) ->
    handle_list(Req0);
handle(<<"GET">>, [Id], Req0) ->
    P = cowboy_req:path(Req0),
    case binary:match(P, <<"/documents">>) of
        {_, _} -> handle_list_documents(Id, Req0);
        nomatch -> handle_get(Id, Req0)
    end;
handle(<<"POST">>, [Id], Req0) ->
    P = cowboy_req:path(Req0),
    case binary:match(P, <<"/documents">>) of
        {_, _} -> handle_add_document(Id, Req0);
        nomatch -> cb_http_util:reply_error(404, <<"not_found">>, Req0)
    end;
handle(<<"POST">>, [Id, Action], Req0) ->
    route_action(Id, Action, Req0);
handle(_, _, Req0) ->
    cb_http_util:reply_error(405, <<"method_not_allowed">>, Req0).

route_action(Id, <<"amend">>, Req0)   -> handle_amend(Id, Req0);
route_action(Id, <<"settle">>, Req0)  -> handle_transition(Id, fun cb_trade_finance:settle_instrument/1, Req0);
route_action(Id, <<"expire">>, Req0)  -> handle_transition(Id, fun cb_trade_finance:expire_instrument/1, Req0);
route_action(Id, <<"cancel">>, Req0)  -> handle_transition(Id, fun cb_trade_finance:cancel_instrument/1, Req0);
route_action(Id, <<"review">>, Req0)  -> handle_review_doc(Id, Req0);
route_action(_,  _,           Req0)   -> cb_http_util:reply_error(404, <<"not_found">>, Req0).

handle_issue(Req0) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req0),
    Params = cb_http_util:decode_json(Body),
    case cb_trade_finance:issue_instrument(Params) of
        {ok, Inst}      -> cb_http_util:reply_json(201, instrument_to_map(Inst), Req1);
        {error, Reason} -> cb_http_util:reply_error(422, Reason, Req1)
    end.

handle_get(InstrumentId, Req0) ->
    case cb_trade_finance:get_instrument(InstrumentId) of
        {ok, Inst}         -> cb_http_util:reply_json(200, instrument_to_map(Inst), Req0);
        {error, not_found} -> cb_http_util:reply_error(404, <<"not_found">>, Req0)
    end.

handle_list(Req0) ->
    QS        = cowboy_req:parse_qs(Req0),
    AccountId = proplists:get_value(<<"account_id">>, QS, undefined),
    Insts     = cb_trade_finance:list_instruments(AccountId),
    cb_http_util:reply_json(200, [instrument_to_map(I) || I <- Insts], Req0).

handle_amend(InstrumentId, Req0) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req0),
    Params = cb_http_util:decode_json(Body),
    case cb_trade_finance:amend_instrument(InstrumentId, Params) of
        {ok, Inst}      -> cb_http_util:reply_json(200, instrument_to_map(Inst), Req1);
        {error, Reason} -> cb_http_util:reply_error(422, Reason, Req1)
    end.

handle_transition(InstrumentId, Fun, Req0) ->
    case Fun(InstrumentId) of
        ok              -> cb_http_util:reply_json(200, #{status => <<"ok">>}, Req0);
        {error, Reason} -> cb_http_util:reply_error(422, Reason, Req0)
    end.

handle_add_document(InstrumentId, Req0) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req0),
    Params = cb_http_util:decode_json(Body),
    case cb_trade_finance:add_document(InstrumentId, Params) of
        {ok, Doc}       -> cb_http_util:reply_json(201, document_to_map(Doc), Req1);
        {error, Reason} -> cb_http_util:reply_error(422, Reason, Req1)
    end.

handle_list_documents(InstrumentId, Req0) ->
    Docs = cb_trade_finance:list_documents(InstrumentId),
    cb_http_util:reply_json(200, [document_to_map(D) || D <- Docs], Req0).

handle_review_doc(DocumentId, Req0) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req0),
    Params  = cb_http_util:decode_json(Body),
    Verdict = binary_to_existing_atom(maps:get(<<"verdict">>, Params), utf8),
    Discs   = maps:get(<<"discrepancies">>, Params, []),
    case cb_trade_finance:review_document(DocumentId, Verdict, Discs) of
        {ok, Doc}       -> cb_http_util:reply_json(200, document_to_map(Doc), Req1);
        {error, Reason} -> cb_http_util:reply_error(422, Reason, Req1)
    end.

%%====================================================================
%% Serialization
%%====================================================================

instrument_to_map(#trade_instrument{
    instrument_id = Id, account_id = AccountId, instrument_type = Type,
    counterparty_id = CpId, currency = Ccy, face_amount = Face,
    status = Status, expiry_date = Expiry, documents = Docs,
    issued_at = IssuedAt, updated_at = UpdatedAt
}) ->
    #{
        instrument_id   => Id,
        account_id      => AccountId,
        instrument_type => Type,
        counterparty_id => CpId,
        currency        => Ccy,
        face_amount     => Face,
        status          => Status,
        expiry_date     => Expiry,
        documents       => Docs,
        issued_at       => IssuedAt,
        updated_at      => UpdatedAt
    }.

document_to_map(#trade_document{
    document_id = Id, instrument_id = InstId, document_type = DocType,
    status = Status, discrepancies = Discs,
    uploaded_at = UploadedAt, reviewed_at = ReviewedAt
}) ->
    #{
        document_id   => Id,
        instrument_id => InstId,
        document_type => DocType,
        status        => Status,
        discrepancies => Discs,
        uploaded_at   => UploadedAt,
        reviewed_at   => ReviewedAt
    }.
