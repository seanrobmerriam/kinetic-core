-module(cb_audit_chain_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, init_per_testcase/2, end_per_suite/1]).
-export([
    append_genesis_link/1,
    append_chained_links/1,
    head_returns_latest/1,
    get_link_by_sequence_ok/1,
    list_links_range/1,
    verify_chain_clean/1,
    verify_chain_detects_tamper/1
]).

all() ->
    [
        append_genesis_link,
        append_chained_links,
        head_returns_latest,
        get_link_by_sequence_ok,
        list_links_range,
        verify_chain_clean,
        verify_chain_detects_tamper
    ].

init_per_suite(Config) ->
    mnesia:start(),
    cb_schema:create_tables(),
    Config.

init_per_testcase(_Case, Config) ->
    %% Reset chain so per-test sequencing is predictable.
    {atomic, ok} = mnesia:clear_table(audit_chain_link),
    {atomic, ok} = mnesia:clear_table(ledger_entry),
    Config.

end_per_suite(_Config) ->
    mnesia:stop(),
    ok.

append_genesis_link(_Config) ->
    {ok, LinkId, Hash} = cb_audit_chain:append(<<"entry-1">>, 1000, 5000),
    ?assert(is_binary(LinkId)),
    ?assertEqual(64, byte_size(Hash)),
    {ok, L} = cb_audit_chain:get_link(LinkId),
    ?assertEqual(1, L#audit_chain_link.sequence).

append_chained_links(_Config) ->
    {ok, _, H1} = cb_audit_chain:append(<<"entry-1">>, 1000, 100),
    {ok, _, H2} = cb_audit_chain:append(<<"entry-2">>, 1001, 200),
    ?assertNotEqual(H1, H2),
    {ok, L2} = cb_audit_chain:get_link_by_sequence(2),
    ?assertEqual(H1, L2#audit_chain_link.prev_hash).

head_returns_latest(_Config) ->
    none = cb_audit_chain:head(),
    {ok, _, _} = cb_audit_chain:append(<<"entry-1">>, 1, 1),
    {ok, _, _} = cb_audit_chain:append(<<"entry-2">>, 2, 2),
    {ok, _, _} = cb_audit_chain:append(<<"entry-3">>, 3, 3),
    {ok, H} = cb_audit_chain:head(),
    ?assertEqual(3, H#audit_chain_link.sequence).

get_link_by_sequence_ok(_Config) ->
    {ok, _, _} = cb_audit_chain:append(<<"entry-1">>, 1, 1),
    {ok, L} = cb_audit_chain:get_link_by_sequence(1),
    ?assertEqual(<<"entry-1">>, L#audit_chain_link.entry_id),
    {error, not_found} = cb_audit_chain:get_link_by_sequence(99).

list_links_range(_Config) ->
    [{ok, _, _} = cb_audit_chain:append(<<"e">>, N, N) || N <- lists:seq(1, 5)],
    Links = cb_audit_chain:list_links(2, 4),
    ?assertEqual(3, length(Links)),
    Seqs = [L#audit_chain_link.sequence || L <- Links],
    ?assertEqual([2, 3, 4], Seqs).

verify_chain_clean(_Config) ->
    Now = erlang:system_time(millisecond),
    write_entry(<<"e1">>, Now, 100),
    write_entry(<<"e2">>, Now + 1, 200),
    {ok, _, _} = cb_audit_chain:append(<<"e1">>, Now, 100),
    {ok, _, _} = cb_audit_chain:append(<<"e2">>, Now + 1, 200),
    {ok, #{checked := 2}} = cb_audit_chain:verify_chain().

verify_chain_detects_tamper(_Config) ->
    Now = erlang:system_time(millisecond),
    write_entry(<<"t1">>, Now, 100),
    {ok, _, _} = cb_audit_chain:append(<<"t1">>, Now, 100),
    %% Tamper with the underlying entry
    write_entry(<<"t1">>, Now, 999),
    {error, #{at_sequence := 1, reason := link_hash_mismatch}} =
        cb_audit_chain:verify_chain().

write_entry(EntryId, PostedAt, Amount) ->
    Entry = #ledger_entry{
        entry_id    = EntryId,
        txn_id      = <<"txn">>,
        account_id  = <<"acc">>,
        entry_type  = debit,
        amount      = Amount,
        currency    = 'USD',
        description = <<"test">>,
        posted_at   = PostedAt
    },
    {atomic, ok} = mnesia:transaction(fun() -> mnesia:write(Entry) end),
    ok.
