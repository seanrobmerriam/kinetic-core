%%%-------------------------------------------------------------------
%% @doc Customer segmentation (P5-S1, TASK-075).
%%
%% Segments are descriptor records; rule evaluation is the caller's
%% responsibility. This module persists segment definitions and
%% membership assignments.
%% @end
%%%-------------------------------------------------------------------
-module(cb_segmentation).

-include_lib("cb_ledger/include/cb_ledger.hrl").
-include_lib("cb_analytics/include/cb_analytics.hrl").

-export([
    define_segment/3,
    list_segments/0,
    get_segment/1,
    retire_segment/1,
    assign/2,
    list_members/1,
    list_segments_for_party/1
]).

-spec define_segment(binary(), binary(), binary()) -> {ok, uuid()}.
define_segment(Name, Description, Rule) ->
    Id = new_id(),
    Now = now_ms(),
    Seg = #customer_segment{
        segment_id  = Id,
        name        = Name,
        description = Description,
        rule        = Rule,
        status      = active,
        created_at  = Now,
        updated_at  = Now
    },
    {atomic, ok} = mnesia:transaction(fun() -> mnesia:write(Seg) end),
    {ok, Id}.

-spec list_segments() -> [#customer_segment{}].
list_segments() ->
    {atomic, L} = mnesia:transaction(fun() ->
        mnesia:foldl(fun(S, Acc) -> [S | Acc] end, [], customer_segment)
    end),
    L.

-spec get_segment(uuid()) -> {ok, #customer_segment{}} | {error, not_found}.
get_segment(SegmentId) ->
    case mnesia:transaction(fun() -> mnesia:read(customer_segment, SegmentId) end) of
        {atomic, [Seg]} -> {ok, Seg};
        {atomic, []}    -> {error, not_found}
    end.

-spec retire_segment(uuid()) -> ok | {error, not_found}.
retire_segment(SegmentId) ->
    F = fun() ->
        case mnesia:read(customer_segment, SegmentId) of
            [S] ->
                mnesia:write(S#customer_segment{status = retired,
                                                updated_at = now_ms()});
            [] ->
                {error, not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, ok}                 -> ok;
        {atomic, {error, not_found}} -> {error, not_found}
    end.

-spec assign(uuid(), uuid()) ->
    {ok, uuid()} | {error, segment_not_found | segment_retired | already_member}.
assign(SegmentId, PartyId) ->
    F = fun() ->
        case mnesia:read(customer_segment, SegmentId) of
            [] ->
                {error, segment_not_found};
            [#customer_segment{status = retired}] ->
                {error, segment_retired};
            [#customer_segment{status = active}] ->
                Existing =
                    [M || M <- mnesia:index_read(segment_membership,
                                                 SegmentId, segment_id),
                          M#segment_membership.party_id =:= PartyId],
                case Existing of
                    [_ | _] ->
                        {error, already_member};
                    [] ->
                        Id = new_id(),
                        M = #segment_membership{
                            membership_id = Id,
                            segment_id    = SegmentId,
                            party_id      = PartyId,
                            assigned_at   = now_ms()
                        },
                        mnesia:write(M),
                        {ok, Id}
                end
        end
    end,
    case mnesia:transaction(F) of
        {atomic, {ok, Id}}       -> {ok, Id};
        {atomic, {error, R}}     -> {error, R}
    end.

-spec list_members(uuid()) -> [#segment_membership{}].
list_members(SegmentId) ->
    {atomic, L} = mnesia:transaction(fun() ->
        mnesia:index_read(segment_membership, SegmentId, segment_id)
    end),
    L.

-spec list_segments_for_party(uuid()) -> [#segment_membership{}].
list_segments_for_party(PartyId) ->
    {atomic, L} = mnesia:transaction(fun() ->
        mnesia:index_read(segment_membership, PartyId, party_id)
    end),
    L.

new_id() ->
    uuid:uuid_to_string(uuid:get_v4(), binary_standard).

now_ms() ->
    erlang:system_time(millisecond).
