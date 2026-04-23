%% @doc Trade Finance Instruments (TASK-063)
%%
%% Manages letters of credit, documentary collections, bank guarantees,
%% and supply chain finance instruments, including document review workflow.
%%
%% == Workflow ==
%% issue → document upload → review (compliant | discrepant) → settle | expire
-module(cb_trade_finance).

-compile({parse_transform, ms_transform}).

-include("../../cb_ledger/include/cb_ledger.hrl").

-export([
    issue_instrument/1,
    get_instrument/1,
    list_instruments/1,
    amend_instrument/2,
    settle_instrument/1,
    expire_instrument/1,
    cancel_instrument/1,
    add_document/2,
    review_document/3,
    list_documents/1
]).

-spec issue_instrument(map()) -> {ok, #trade_instrument{}} | {error, term()}.
issue_instrument(Params) ->
    Now = erlang:system_time(millisecond),
    Inst = #trade_instrument{
        instrument_id   = uuid:get_v4(),
        account_id      = maps:get(account_id, Params),
        instrument_type = maps:get(instrument_type, Params),
        counterparty_id = maps:get(counterparty_id, Params),
        currency        = maps:get(currency, Params),
        face_amount     = maps:get(face_amount, Params),
        status          = issued,
        expiry_date     = maps:get(expiry_date, Params, undefined),
        documents       = [],
        issued_at       = Now,
        updated_at      = Now
    },
    case mnesia:transaction(fun() -> mnesia:write(Inst) end) of
        {atomic, ok} -> {ok, Inst};
        {aborted, Reason} -> {error, Reason}
    end.

-spec get_instrument(uuid()) -> {ok, #trade_instrument{}} | {error, not_found}.
get_instrument(InstrumentId) ->
    case mnesia:dirty_read(trade_instrument, InstrumentId) of
        [I] -> {ok, I};
        []  -> {error, not_found}
    end.

-spec list_instruments(uuid()) -> [#trade_instrument{}].
list_instruments(AccountId) ->
    MatchSpec = ets:fun2ms(fun(I = #trade_instrument{account_id = A}) when A =:= AccountId -> I end),
    mnesia:dirty_select(trade_instrument, MatchSpec).

-spec amend_instrument(uuid(), map()) -> {ok, #trade_instrument{}} | {error, term()}.
amend_instrument(InstrumentId, Params) ->
    F = fun() ->
        case mnesia:wread({trade_instrument, InstrumentId}) of
            [Inst] ->
                Now = erlang:system_time(millisecond),
                Updated = apply_instrument_updates(Inst, Params, Now),
                mnesia:write(Updated),
                Updated;
            [] -> mnesia:abort(not_found)
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Updated} -> {ok, Updated};
        {aborted, Reason} -> {error, Reason}
    end.

-spec settle_instrument(uuid()) -> ok | {error, term()}.
settle_instrument(InstrumentId) ->
    transition_status(InstrumentId, settled).

-spec expire_instrument(uuid()) -> ok | {error, term()}.
expire_instrument(InstrumentId) ->
    transition_status(InstrumentId, expired).

-spec cancel_instrument(uuid()) -> ok | {error, term()}.
cancel_instrument(InstrumentId) ->
    transition_status(InstrumentId, cancelled).

-spec add_document(uuid(), map()) -> {ok, #trade_document{}} | {error, term()}.
add_document(InstrumentId, Params) ->
    Now = erlang:system_time(millisecond),
    Doc = #trade_document{
        document_id   = uuid:get_v4(),
        instrument_id = InstrumentId,
        document_type = maps:get(document_type, Params),
        status        = pending,
        discrepancies = [],
        uploaded_at   = Now,
        reviewed_at   = undefined
    },
    F = fun() ->
        case mnesia:wread({trade_instrument, InstrumentId}) of
            [Inst] ->
                mnesia:write(Doc),
                Docs = Inst#trade_instrument.documents,
                mnesia:write(Inst#trade_instrument{
                    documents  = [Doc#trade_document.document_id | Docs],
                    updated_at = Now
                });
            [] -> mnesia:abort(not_found)
        end
    end,
    case mnesia:transaction(F) of
        {atomic, ok} -> {ok, Doc};
        {aborted, Reason} -> {error, Reason}
    end.

-spec review_document(uuid(), compliant | discrepant, [binary()]) ->
    {ok, #trade_document{}} | {error, term()}.
review_document(DocumentId, Verdict, Discrepancies) ->
    F = fun() ->
        case mnesia:wread({trade_document, DocumentId}) of
            [Doc] ->
                Now = erlang:system_time(millisecond),
                Updated = Doc#trade_document{
                    status        = Verdict,
                    discrepancies = Discrepancies,
                    reviewed_at   = Now
                },
                mnesia:write(Updated),
                Updated;
            [] -> mnesia:abort(not_found)
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Updated} -> {ok, Updated};
        {aborted, Reason} -> {error, Reason}
    end.

-spec list_documents(uuid()) -> [#trade_document{}].
list_documents(InstrumentId) ->
    MatchSpec = ets:fun2ms(fun(D = #trade_document{instrument_id = I}) when I =:= InstrumentId -> D end),
    mnesia:dirty_select(trade_document, MatchSpec).

%%====================================================================
%% Internal helpers
%%====================================================================

-spec transition_status(uuid(), trade_instrument_status()) -> ok | {error, term()}.
transition_status(InstrumentId, Status) ->
    F = fun() ->
        case mnesia:wread({trade_instrument, InstrumentId}) of
            [Inst] ->
                Now = erlang:system_time(millisecond),
                mnesia:write(Inst#trade_instrument{status = Status, updated_at = Now});
            [] -> mnesia:abort(not_found)
        end
    end,
    case mnesia:transaction(F) of
        {atomic, ok}      -> ok;
        {aborted, Reason} -> {error, Reason}
    end.

-spec apply_instrument_updates(#trade_instrument{}, map(), timestamp_ms()) -> #trade_instrument{}.
apply_instrument_updates(Inst, Params, Now) ->
    Inst#trade_instrument{
        face_amount = maps:get(face_amount, Params, Inst#trade_instrument.face_amount),
        expiry_date = maps:get(expiry_date, Params, Inst#trade_instrument.expiry_date),
        status      = amended,
        updated_at  = Now
    }.
