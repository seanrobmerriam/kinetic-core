%% @doc Event replay-based ledger state recovery (TASK-072).
%%
%% A replay_session reconstructs ledger state by reapplying ledger entries
%% within a time window. Each replayed entry produces a replay_event record
%% with an outcome (ok | skipped | error). Sessions move through:
%%   pending → running → completed | failed | aborted.
-module(cb_ledger_replay).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    start_session/3,
    get_session/1,
    list_sessions/0,
    record_event/4,
    list_events/1,
    complete_session/1,
    fail_session/2,
    abort_session/1
]).

-spec start_session(binary(), timestamp_ms(), timestamp_ms()) ->
    {ok, uuid()} | {error, term()}.
start_session(Scope, FromMs, ToMs)
        when is_binary(Scope), is_integer(FromMs), is_integer(ToMs),
             FromMs =< ToMs ->
    SessionId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
    Now = erlang:system_time(millisecond),
    Session = #replay_session{
        session_id    = SessionId,
        scope         = Scope,
        from_ms       = FromMs,
        to_ms         = ToMs,
        status        = running,
        applied_count = 0,
        started_at    = Now,
        completed_at  = undefined,
        last_error    = undefined
    },
    case mnesia:transaction(fun() -> mnesia:write(Session) end) of
        {atomic, ok}      -> {ok, SessionId};
        {aborted, Reason} -> {error, Reason}
    end;
start_session(_, _, _) ->
    {error, invalid_window}.

-spec get_session(uuid()) -> {ok, #replay_session{}} | {error, not_found}.
get_session(SessionId) ->
    case mnesia:dirty_read(replay_session, SessionId) of
        [S] -> {ok, S};
        []  -> {error, not_found}
    end.

-spec list_sessions() -> [#replay_session{}].
list_sessions() ->
    {atomic, Sessions} = mnesia:transaction(fun() ->
        mnesia:foldl(fun(S, Acc) -> [S | Acc] end, [], replay_session)
    end),
    lists:sort(fun(A, B) -> A#replay_session.started_at >= B#replay_session.started_at end, Sessions).

-spec record_event(uuid(), uuid(), ok | skipped | error, binary() | undefined) ->
    {ok, uuid()} | {error, not_found | invalid_status}.
record_event(SessionId, EntryId, Outcome, Note)
        when is_binary(SessionId), is_binary(EntryId),
             (Outcome =:= ok orelse Outcome =:= skipped orelse Outcome =:= error) ->
    EventId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
    Now = erlang:system_time(millisecond),
    F = fun() ->
        case mnesia:read(replay_session, SessionId) of
            [S = #replay_session{status = running}] ->
                Event = #replay_event{
                    event_id   = EventId,
                    session_id = SessionId,
                    entry_id   = EntryId,
                    applied_at = Now,
                    outcome    = Outcome,
                    note       = Note
                },
                mnesia:write(Event),
                mnesia:write(S#replay_session{
                    applied_count = S#replay_session.applied_count + 1
                }),
                {ok, EventId};
            [_] ->
                {error, invalid_status};
            [] ->
                {error, not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, {ok, Id}}                 -> {ok, Id};
        {atomic, {error, invalid_status}}  -> {error, invalid_status};
        {atomic, {error, not_found}}       -> {error, not_found};
        {aborted, Reason}                  -> {error, Reason}
    end;
record_event(_, _, _, _) ->
    {error, invalid_arguments}.

-spec list_events(uuid()) -> [#replay_event{}].
list_events(SessionId) ->
    {atomic, Events} = mnesia:transaction(fun() ->
        mnesia:index_read(replay_event, SessionId, session_id)
    end),
    lists:sort(fun(A, B) -> A#replay_event.applied_at =< B#replay_event.applied_at end, Events).

-spec complete_session(uuid()) -> ok | {error, not_found | invalid_status}.
complete_session(SessionId) ->
    transition(SessionId, completed, undefined).

-spec fail_session(uuid(), binary()) -> ok | {error, not_found | invalid_status}.
fail_session(SessionId, Error) when is_binary(Error) ->
    transition(SessionId, failed, Error).

-spec abort_session(uuid()) -> ok | {error, not_found | invalid_status}.
abort_session(SessionId) ->
    transition(SessionId, aborted, undefined).

transition(SessionId, NewStatus, Error) ->
    F = fun() ->
        case mnesia:read(replay_session, SessionId) of
            [S = #replay_session{status = running}] ->
                Now = erlang:system_time(millisecond),
                mnesia:write(S#replay_session{
                    status       = NewStatus,
                    completed_at = Now,
                    last_error   = Error
                });
            [_] ->
                {error, invalid_status};
            [] ->
                {error, not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, ok}                       -> ok;
        {atomic, {error, invalid_status}}  -> {error, invalid_status};
        {atomic, {error, not_found}}       -> {error, not_found};
        {aborted, Reason}                  -> {error, Reason}
    end.
