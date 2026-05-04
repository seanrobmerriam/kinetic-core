%% @doc HTTP handler for ledger replay sessions (TASK-072).
%%
%% Routes:
%%   GET  /api/v1/ledger/replay/sessions                     — list sessions
%%   POST /api/v1/ledger/replay/sessions                     — start session
%%   GET  /api/v1/ledger/replay/sessions/:session_id         — get session
%%   POST /api/v1/ledger/replay/sessions/:session_id/:action — complete|fail|abort|events
%%   GET  /api/v1/ledger/replay/sessions/:session_id/events  — list events
-module(cb_ledger_replay_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

init(Req, State) ->
    Method    = cowboy_req:method(Req),
    SessionId = cowboy_req:binding(session_id, Req),
    Action    = cowboy_req:binding(action, Req),
    handle(Method, SessionId, Action, Req, State).

handle(<<"GET">>, undefined, undefined, Req, State) ->
    Sessions = cb_ledger_replay:list_sessions(),
    R = cowboy_req:reply(200, headers(),
            jsone:encode(#{sessions => [session_to_map(S) || S <- Sessions]}), Req),
    {ok, R, State};

handle(<<"POST">>, undefined, undefined, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{scope := Scope, from_ms := From, to_ms := To}, _}
                when is_binary(Scope), is_integer(From), is_integer(To) ->
            case cb_ledger_replay:start_session(Scope, From, To) of
                {ok, SessionId} ->
                    R = cowboy_req:reply(201, headers(),
                            jsone:encode(#{session_id => SessionId}), Req2),
                    {ok, R, State};
                {error, Reason} ->
                    error_reply(400, Reason, Req2, State)
            end;
        _ ->
            error_reply(400,
                <<"Missing required fields: scope, from_ms, to_ms">>,
                Req2, State)
    end;

handle(<<"GET">>, SessionId, undefined, Req, State) ->
    case cb_ledger_replay:get_session(SessionId) of
        {ok, S} ->
            R = cowboy_req:reply(200, headers(),
                    jsone:encode(session_to_map(S)), Req),
            {ok, R, State};
        {error, not_found} ->
            error_reply(404, <<"Session not found">>, Req, State)
    end;

handle(<<"GET">>, SessionId, <<"events">>, Req, State) ->
    Events = cb_ledger_replay:list_events(SessionId),
    R = cowboy_req:reply(200, headers(),
            jsone:encode(#{events => [event_to_map(E) || E <- Events]}), Req),
    {ok, R, State};

handle(<<"POST">>, SessionId, <<"events">>, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{entry_id := EntryId, outcome := OutcomeBin} = Map, _} ->
            Note = maps:get(note, Map, undefined),
            case parse_outcome(OutcomeBin) of
                {ok, Outcome} ->
                    case cb_ledger_replay:record_event(SessionId, EntryId, Outcome, Note) of
                        {ok, EventId} ->
                            R = cowboy_req:reply(201, headers(),
                                    jsone:encode(#{event_id => EventId}), Req2),
                            {ok, R, State};
                        {error, not_found} ->
                            error_reply(404, <<"Session not found">>, Req2, State);
                        {error, Reason} ->
                            error_reply(400, Reason, Req2, State)
                    end;
                error ->
                    error_reply(400, <<"Invalid outcome">>, Req2, State)
            end;
        _ ->
            error_reply(400,
                <<"Missing required fields: entry_id, outcome">>, Req2, State)
    end;

handle(<<"POST">>, SessionId, <<"complete">>, Req, State) ->
    transition_reply(cb_ledger_replay:complete_session(SessionId), Req, State);
handle(<<"POST">>, SessionId, <<"abort">>, Req, State) ->
    transition_reply(cb_ledger_replay:abort_session(SessionId), Req, State);
handle(<<"POST">>, SessionId, <<"fail">>, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    Err = case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{error := E}, _} when is_binary(E) -> E;
        _                                        -> <<"unspecified">>
    end,
    transition_reply(cb_ledger_replay:fail_session(SessionId, Err), Req2, State);

handle(_, _, _, Req, State) ->
    error_reply(405, <<"Method not allowed">>, Req, State).

parse_outcome(<<"ok">>)      -> {ok, ok};
parse_outcome(<<"skipped">>) -> {ok, skipped};
parse_outcome(<<"error">>)   -> {ok, error};
parse_outcome(_)             -> error.

transition_reply(ok, Req, State) ->
    R = cowboy_req:reply(200, headers(),
            jsone:encode(#{status => <<"updated">>}), Req),
    {ok, R, State};
transition_reply({error, not_found}, Req, State) ->
    error_reply(404, <<"Session not found">>, Req, State);
transition_reply({error, Reason}, Req, State) ->
    error_reply(400, Reason, Req, State).

session_to_map(S) ->
    #{session_id    => S#replay_session.session_id,
      scope         => S#replay_session.scope,
      from_ms       => S#replay_session.from_ms,
      to_ms         => S#replay_session.to_ms,
      status        => S#replay_session.status,
      applied_count => S#replay_session.applied_count,
      started_at    => S#replay_session.started_at,
      completed_at  => S#replay_session.completed_at,
      last_error    => S#replay_session.last_error}.

event_to_map(E) ->
    #{event_id   => E#replay_event.event_id,
      session_id => E#replay_event.session_id,
      entry_id   => E#replay_event.entry_id,
      applied_at => E#replay_event.applied_at,
      outcome    => E#replay_event.outcome,
      note       => E#replay_event.note}.

headers() ->
    #{<<"content-type">> => <<"application/json">>}.

error_reply(Code, Reason, Req, State) when is_atom(Reason) ->
    error_reply(Code, atom_to_binary(Reason, utf8), Req, State);
error_reply(Code, Reason, Req, State) ->
    R = cowboy_req:reply(Code, headers(),
            jsone:encode(#{error => Reason}), Req),
    {ok, R, State}.
