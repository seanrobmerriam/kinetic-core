-module(cb_channel_session).

-include("../../cb_ledger/include/cb_ledger.hrl").

-export([
    create/2,
    get/1,
    list_for_party/1,
    invalidate/1,
    invalidate_all_for_party/1
]).

-spec create(uuid(), channel_type()) -> {ok, #channel_session{}} | {error, atom()}.
create(PartyId, Channel) ->
    SessionId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
    Now = erlang:system_time(millisecond),
    Session = #channel_session{
        session_id     = SessionId,
        party_id       = PartyId,
        channel        = Channel,
        status         = active,
        initiated_at   = Now,
        invalidated_at = undefined,
        metadata       = #{}
    },
    case mnesia:transaction(fun() -> mnesia:write(Session) end) of
        {atomic, ok} -> {ok, Session};
        {aborted, Reason} -> {error, Reason}
    end.

-spec get(uuid()) -> {ok, #channel_session{}} | {error, not_found}.
get(SessionId) ->
    case mnesia:dirty_read(channel_session, SessionId) of
        [Session] -> {ok, Session};
        []        -> {error, not_found}
    end.

-spec list_for_party(uuid()) -> {ok, [#channel_session{}]}.
list_for_party(PartyId) ->
    Sessions = mnesia:dirty_index_read(channel_session, PartyId, party_id),
    {ok, Sessions}.

-spec invalidate(uuid()) -> {ok, #channel_session{}} | {error, not_found | atom()}.
invalidate(SessionId) ->
    Now = erlang:system_time(millisecond),
    F = fun() ->
        case mnesia:read(channel_session, SessionId) of
            [] ->
                mnesia:abort(not_found);
            [Session] ->
                Updated = Session#channel_session{
                    status         = invalidated,
                    invalidated_at = Now
                },
                mnesia:write(Updated),
                Updated
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Session} -> {ok, Session};
        {aborted, not_found} -> {error, not_found};
        {aborted, Reason}    -> {error, Reason}
    end.

-spec invalidate_all_for_party(uuid()) -> {ok, non_neg_integer()} | {error, atom()}.
invalidate_all_for_party(PartyId) ->
    Now = erlang:system_time(millisecond),
    F = fun() ->
        Sessions = mnesia:index_read(channel_session, PartyId, party_id),
        Active = [S || S <- Sessions, S#channel_session.status =:= active],
        lists:foreach(fun(S) ->
            mnesia:write(S#channel_session{status = invalidated, invalidated_at = Now})
        end, Active),
        length(Active)
    end,
    case mnesia:transaction(F) of
        {atomic, Count} -> {ok, Count};
        {aborted, Reason} -> {error, Reason}
    end.
