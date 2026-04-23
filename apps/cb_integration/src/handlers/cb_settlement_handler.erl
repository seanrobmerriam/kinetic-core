%% @doc HTTP handler for settlement and reconciliation (TASK-061).
%%
%% Routes:
%%   GET  /api/v1/settlements                             — list runs
%%   POST /api/v1/settlements                             — create run
%%   GET  /api/v1/settlements/:run_id                     — get run report
%%   POST /api/v1/settlements/:run_id/entries             — add expected entry
%%   POST /api/v1/settlements/:run_id/reconcile           — auto-reconcile
%%   POST /api/v1/settlements/:run_id/close               — close run
%%   GET  /api/v1/settlements/:run_id/unmatched           — list unmatched entries
-module(cb_settlement_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

init(Req, State) ->
    Method = cowboy_req:method(Req),
    RunId  = cowboy_req:binding(run_id, Req),
    Action = cowboy_req:binding(action, Req),
    handle(Method, RunId, Action, Req, State).

handle(<<"GET">>, undefined, undefined, Req, State) ->
    Runs = cb_settlement:list_runs(),
    Req2 = cowboy_req:reply(200, headers(),
               jsone:encode(#{runs => [run_to_map(R) || R <- Runs]}), Req),
    {ok, Req2, State};

handle(<<"POST">>, undefined, undefined, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{rail := Rail}, _} ->
            case cb_settlement:create_run(#{rail => Rail}) of
                {ok, RunId} ->
                    Req3 = cowboy_req:reply(201, headers(),
                               jsone:encode(#{run_id => RunId}), Req2),
                    {ok, Req3, State};
                {error, Reason} ->
                    error_reply(500, Reason, Req2, State)
            end;
        _ ->
            error_reply(400, <<"Missing required field: rail">>, Req2, State)
    end;

handle(<<"GET">>, RunId, undefined, Req, State) ->
    case cb_settlement:get_report(RunId) of
        {ok, Report} ->
            Req2 = cowboy_req:reply(200, headers(), jsone:encode(Report), Req),
            {ok, Req2, State};
        {error, not_found} ->
            error_reply(404, <<"Settlement run not found">>, Req, State)
    end;

handle(<<"POST">>, RunId, <<"entries">>, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{payment_id := PaymentId, expected_amount := Amount,
               currency := Currency}, _} ->
            Params = #{payment_id      => PaymentId,
                       expected_amount => Amount,
                       currency        => Currency},
            case cb_settlement:add_entry(RunId, Params) of
                {ok, EntryId} ->
                    Req3 = cowboy_req:reply(201, headers(),
                               jsone:encode(#{entry_id => EntryId}), Req2),
                    {ok, Req3, State};
                {error, Reason} ->
                    error_reply(400, Reason, Req2, State)
            end;
        _ ->
            error_reply(400,
                <<"Missing required fields: payment_id, expected_amount, currency">>,
                Req2, State)
    end;

handle(<<"POST">>, RunId, <<"reconcile">>, Req, State) ->
    case cb_settlement:auto_reconcile(RunId) of
        {ok, Summary} ->
            Req2 = cowboy_req:reply(200, headers(), jsone:encode(Summary), Req),
            {ok, Req2, State};
        {error, Reason} ->
            error_reply(400, Reason, Req, State)
    end;

handle(<<"POST">>, RunId, <<"close">>, Req, State) ->
    case cb_settlement:close_run(RunId) of
        ok ->
            Req2 = cowboy_req:reply(200, headers(),
                       jsone:encode(#{status => <<"closed">>}), Req),
            {ok, Req2, State};
        {error, Reason} ->
            error_reply(400, Reason, Req, State)
    end;

handle(<<"GET">>, RunId, <<"unmatched">>, Req, State) ->
    Entries = cb_settlement:list_unmatched(RunId),
    Req2 = cowboy_req:reply(200, headers(),
               jsone:encode(#{entries => [entry_to_map(E) || E <- Entries]}), Req),
    {ok, Req2, State};

handle(_Method, _RunId, _Action, Req, State) ->
    error_reply(405, <<"Method not allowed">>, Req, State).

%%--------------------------------------------------------------------
%% Helpers
%%--------------------------------------------------------------------

run_to_map(R) ->
    #{run_id         => R#settlement_run.run_id,
      rail           => R#settlement_run.rail,
      status         => R#settlement_run.status,
      expected_total => R#settlement_run.expected_total,
      actual_total   => R#settlement_run.actual_total,
      opened_at      => R#settlement_run.opened_at,
      closed_at      => R#settlement_run.closed_at,
      reconciled_at  => R#settlement_run.reconciled_at}.

entry_to_map(E) ->
    #{entry_id        => E#reconciliation_entry.entry_id,
      run_id          => E#reconciliation_entry.run_id,
      payment_id      => E#reconciliation_entry.payment_id,
      ledger_entry_id => E#reconciliation_entry.ledger_entry_id,
      expected_amount => E#reconciliation_entry.expected_amount,
      actual_amount   => E#reconciliation_entry.actual_amount,
      currency        => E#reconciliation_entry.currency,
      match_status    => E#reconciliation_entry.match_status}.

headers() ->
    #{<<"content-type">> => <<"application/json">>}.

error_reply(Code, Reason, Req, State) when is_atom(Reason) ->
    error_reply(Code, atom_to_binary(Reason, utf8), Req, State);
error_reply(Code, Reason, Req, State) ->
    Req2 = cowboy_req:reply(Code, headers(),
               jsone:encode(#{error => Reason}), Req),
    {ok, Req2, State}.
