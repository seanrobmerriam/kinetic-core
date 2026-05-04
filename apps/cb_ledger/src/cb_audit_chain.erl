%% @doc Cryptographic audit-chain over ledger entries (TASK-073).
%%
%% Each new audit_chain_link is appended with a SHA-256 hash that includes
%% the previous link's hash. This produces a tamper-evident chain: any
%% modification to a historical entry breaks every subsequent link_hash.
%%
%% Hashes are stored as lowercase hex binaries.
-module(cb_audit_chain).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    append/1,
    append/3,
    get_link/1,
    get_link_by_sequence/1,
    list_links/2,
    head/0,
    verify_chain/0
]).

-define(GENESIS_HASH,
        <<"0000000000000000000000000000000000000000000000000000000000000000">>).

%% @doc Append a link for a posted ledger entry. Reads required fields
%% from the entry record.
-spec append(#ledger_entry{}) -> {ok, uuid(), binary()} | {error, term()}.
append(#ledger_entry{entry_id = EntryId, posted_at = PostedAt, amount = Amount}) ->
    append(EntryId, PostedAt, Amount).

-spec append(uuid(), timestamp_ms(), amount()) ->
    {ok, uuid(), binary()} | {error, term()}.
append(EntryId, PostedAt, Amount)
        when is_binary(EntryId), is_integer(PostedAt), is_integer(Amount) ->
    LinkId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
    Now = erlang:system_time(millisecond),
    F = fun() ->
        {Sequence, PrevHash} = case head_inner() of
            {ok, H} -> {H#audit_chain_link.sequence + 1, H#audit_chain_link.link_hash};
            none    -> {1, ?GENESIS_HASH}
        end,
        LinkHash = compute_hash(PrevHash, Sequence, EntryId, PostedAt, Amount),
        Link = #audit_chain_link{
            link_id    = LinkId,
            sequence   = Sequence,
            entry_id   = EntryId,
            prev_hash  = PrevHash,
            link_hash  = LinkHash,
            created_at = Now
        },
        mnesia:write(Link),
        {ok, LinkId, LinkHash}
    end,
    case mnesia:transaction(F) of
        {atomic, {ok, Id, Hash}} -> {ok, Id, Hash};
        {aborted, Reason}        -> {error, Reason}
    end;
append(_, _, _) ->
    {error, invalid_arguments}.

-spec get_link(uuid()) -> {ok, #audit_chain_link{}} | {error, not_found}.
get_link(LinkId) ->
    case mnesia:dirty_read(audit_chain_link, LinkId) of
        [L] -> {ok, L};
        []  -> {error, not_found}
    end.

-spec get_link_by_sequence(pos_integer()) ->
    {ok, #audit_chain_link{}} | {error, not_found}.
get_link_by_sequence(Sequence) when is_integer(Sequence), Sequence >= 1 ->
    {atomic, Links} = mnesia:transaction(fun() ->
        mnesia:index_read(audit_chain_link, Sequence, sequence)
    end),
    case Links of
        [L] -> {ok, L};
        _   -> {error, not_found}
    end.

-spec list_links(pos_integer(), pos_integer()) -> [#audit_chain_link{}].
list_links(FromSeq, ToSeq)
        when is_integer(FromSeq), is_integer(ToSeq), FromSeq =< ToSeq ->
    {atomic, Links} = mnesia:transaction(fun() ->
        mnesia:foldl(fun(L, Acc) -> [L | Acc] end, [], audit_chain_link)
    end),
    Filtered = [L || L <- Links,
                     L#audit_chain_link.sequence >= FromSeq,
                     L#audit_chain_link.sequence =< ToSeq],
    lists:sort(fun(A, B) -> A#audit_chain_link.sequence =< B#audit_chain_link.sequence end, Filtered).

-spec head() -> {ok, #audit_chain_link{}} | none.
head() ->
    case mnesia:transaction(fun() -> head_inner() end) of
        {atomic, Result}  -> Result;
        {aborted, _Reason} -> none
    end.

%% @private Must be called from within a Mnesia transaction.
-spec head_inner() -> {ok, #audit_chain_link{}} | none.
head_inner() ->
    All = mnesia:foldl(fun(L, Acc) -> [L | Acc] end, [], audit_chain_link),
    case All of
        []   -> none;
        Some ->
            Sorted = lists:sort(
                fun(A, B) -> A#audit_chain_link.sequence >= B#audit_chain_link.sequence end,
                Some),
            {ok, hd(Sorted)}
    end.

%% @doc Walk every link in sequence order and verify its link_hash matches
%% the recomputed hash of (prev_hash || sequence || entry_id || posted_at ||
%% amount). The amount/posted_at are pulled live from the referenced
%% ledger_entry; if the entry has been altered or removed, verification
%% fails for that link.
-spec verify_chain() ->
    {ok, #{checked := non_neg_integer()}} |
    {error, #{at_sequence := pos_integer(),
              reason := entry_missing | link_hash_mismatch | prev_hash_mismatch}}.
verify_chain() ->
    Links = list_links(1, max_seq()),
    verify_chain(Links, ?GENESIS_HASH, 0).

verify_chain([], _PrevHash, Count) ->
    {ok, #{checked => Count}};
verify_chain([L | Rest], PrevHash, Count) ->
    case L#audit_chain_link.prev_hash =:= PrevHash of
        false ->
            {error, #{at_sequence => L#audit_chain_link.sequence,
                      reason      => prev_hash_mismatch}};
        true ->
            case mnesia:dirty_read(ledger_entry, L#audit_chain_link.entry_id) of
                [E] ->
                    Recomputed = compute_hash(PrevHash,
                                              L#audit_chain_link.sequence,
                                              E#ledger_entry.entry_id,
                                              E#ledger_entry.posted_at,
                                              E#ledger_entry.amount),
                    case Recomputed =:= L#audit_chain_link.link_hash of
                        true ->
                            verify_chain(Rest, L#audit_chain_link.link_hash, Count + 1);
                        false ->
                            {error, #{at_sequence => L#audit_chain_link.sequence,
                                      reason      => link_hash_mismatch}}
                    end;
                [] ->
                    {error, #{at_sequence => L#audit_chain_link.sequence,
                              reason      => entry_missing}}
            end
    end.

max_seq() ->
    case head() of
        {ok, H} -> H#audit_chain_link.sequence;
        none    -> 0
    end.

-spec compute_hash(binary(), pos_integer(), uuid(), timestamp_ms(), amount()) ->
    binary().
compute_hash(PrevHash, Sequence, EntryId, PostedAt, Amount) ->
    Material = <<PrevHash/binary, "|",
                 (integer_to_binary(Sequence))/binary, "|",
                 EntryId/binary, "|",
                 (integer_to_binary(PostedAt))/binary, "|",
                 (integer_to_binary(Amount))/binary>>,
    Digest = crypto:hash(sha256, Material),
    list_to_binary(lists:flatten(
        [io_lib:format("~2.16.0b", [B]) || <<B>> <= Digest])).
