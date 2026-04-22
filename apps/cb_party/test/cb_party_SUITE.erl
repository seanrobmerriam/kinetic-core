-module(cb_party_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    create_party_ok/1,
    create_party_duplicate_email/1,
    get_party_ok/1,
    get_party_not_found/1,
    list_parties_ok/1,
    list_parties_with_status_filter/1,
    suspend_party_ok/1,
    suspend_party_already_suspended/1,
    close_party_ok/1,
    close_party_with_accounts/1,
    update_party_address_increments_version/1,
    detect_duplicate_parties_by_name/1,
    merge_party_transfers_accounts/1
]).

all() ->
    [
        create_party_ok,
        create_party_duplicate_email,
        get_party_ok,
        get_party_not_found,
        list_parties_ok,
        list_parties_with_status_filter,
        suspend_party_ok,
        suspend_party_already_suspended,
        close_party_ok,
        close_party_with_accounts,
        update_party_address_increments_version,
        detect_duplicate_parties_by_name,
        merge_party_transfers_accounts
    ].

init_per_suite(Config) ->
    mnesia:start(),
    cb_schema:create_tables(),
    Config.

end_per_suite(_Config) ->
    mnesia:stop(),
    mnesia:delete_schema([node()]),
    ok.

init_per_testcase(_TestCase, Config) ->
    %% Clear all tables before each test
    lists:foreach(fun(T) -> mnesia:clear_table(T) end,
                  [party, party_audit, account, transaction, ledger_entry]),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

%% Test: Create party with valid data
create_party_ok(_Config) ->
    {ok, Party} = cb_party:create_party(<<"Alice Nguyen">>, <<"alice@example.com">>),
    ?assertEqual(<<"Alice Nguyen">>, Party#party.full_name),
    ?assertEqual(<<"alice@example.com">>, Party#party.email),
    ?assertEqual(active, Party#party.status),
    ?assert(is_binary(Party#party.party_id)),
    ok.

%% Test: Create party with duplicate email
create_party_duplicate_email(_Config) ->
    {ok, _Party} = cb_party:create_party(<<"Alice Nguyen">>, <<"alice@example.com">>),
    {error, Reason} = cb_party:create_party(<<"Alice Smith">>, <<"alice@example.com">>),
    ?assertEqual(email_already_exists, Reason),
    ok.

%% Test: Get existing party
get_party_ok(_Config) ->
    {ok, Party} = cb_party:create_party(<<"Bob Smith">>, <<"bob@example.com">>),
    {ok, Retrieved} = cb_party:get_party(Party#party.party_id),
    ?assertEqual(Party#party.party_id, Retrieved#party.party_id),
    ?assertEqual(<<"Bob Smith">>, Retrieved#party.full_name),
    ok.

%% Test: Get non-existent party
get_party_not_found(_Config) ->
    FakeId = <<"00000000-0000-0000-0000-000000000000">>,
    {error, Reason} = cb_party:get_party(FakeId),
    ?assertEqual(party_not_found, Reason),
    ok.

%% Test: List parties with pagination
list_parties_ok(_Config) ->
    %% Create multiple parties
    {ok, _P1} = cb_party:create_party(<<"Party One">>, <<"one@example.com">>),
    {ok, _P2} = cb_party:create_party(<<"Party Two">>, <<"two@example.com">>),
    {ok, _P3} = cb_party:create_party(<<"Party Three">>, <<"three@example.com">>),
    
    {ok, Result} = cb_party:list_parties(1, 2),
    ?assertEqual(3, maps:get(total, Result)),
    ?assertEqual(2, length(maps:get(items, Result))),
    ?assertEqual(1, maps:get(page, Result)),
    ?assertEqual(2, maps:get(page_size, Result)),
    ok.

%% Test: List parties with status filter
list_parties_with_status_filter(_Config) ->
    {ok, Party1} = cb_party:create_party(<<"Filter One">>, <<"filter1@example.com">>),
    {ok, _Party2} = cb_party:create_party(<<"Filter Two">>, <<"filter2@example.com">>),
    {ok, _Suspended} = cb_party:suspend_party(Party1#party.party_id),

    {ok, Result} = cb_party:list_parties_filtered(1, 10, #{status => suspended}),
    Items = maps:get(items, Result),
    ?assertEqual(1, length(Items)),
    [Only] = Items,
    ?assertEqual(suspended, Only#party.status),
    ok.

%% Test: Suspend an active party
suspend_party_ok(_Config) ->
    {ok, Party} = cb_party:create_party(<<"Charlie">>, <<"charlie@example.com">>),
    ?assertEqual(active, Party#party.status),
    
    {ok, Suspended} = cb_party:suspend_party(Party#party.party_id),
    ?assertEqual(suspended, Suspended#party.status),
    ok.

%% Test: Suspend already suspended party
suspend_party_already_suspended(_Config) ->
    {ok, Party} = cb_party:create_party(<<"David">>, <<"david@example.com">>),
    {ok, _Suspended} = cb_party:suspend_party(Party#party.party_id),
    
    {error, Reason} = cb_party:suspend_party(Party#party.party_id),
    ?assertEqual(party_already_suspended, Reason),
    ok.

%% Test: Close a party with no active accounts
close_party_ok(_Config) ->
    {ok, Party} = cb_party:create_party(<<"Eve">>, <<"eve@example.com">>),
    {ok, Closed} = cb_party:close_party(Party#party.party_id),
    ?assertEqual(closed, Closed#party.status),
    ok.

%% Test: Close a party with active accounts
close_party_with_accounts(_Config) ->
    {ok, Party} = cb_party:create_party(<<"Frank">>, <<"frank@example.com">>),
    
    %% Create an account for this party
    {ok, _Account} = cb_accounts:create_account(Party#party.party_id, <<"Main">>, 'USD'),
    
    {error, Reason} = cb_party:close_party(Party#party.party_id),
    ?assertEqual(party_has_active_accounts, Reason),
    ok.

%% Test: Update party address increments version
update_party_address_increments_version(_Config) ->
    {ok, Party} = cb_party:create_party(<<"Address Test">>, <<"address@example.com">>),
    ?assertEqual(1, Party#party.version),

    Address = #{
        line1 => <<"123 Main St">>,
        line2 => <<"Suite 200">>,
        city => <<"Nairobi">>,
        state => <<"Nairobi County">>,
        postal_code => <<"00100">>,
        country => <<"KE">>
    },
    {ok, Updated} = cb_party:update_address(Party#party.party_id, Address),
    ?assertEqual(Address, Updated#party.address),
    ?assertEqual(2, Updated#party.version),
    ok.

%% Test: Detect duplicate parties by normalized name
detect_duplicate_parties_by_name(_Config) ->
    {ok, _Party1} = cb_party:create_party(<<"Alice Nguyen">>, <<"a1@example.com">>),
    {ok, _Party2} = cb_party:create_party(<<" alice nguyen  ">>, <<"a2@example.com">>),
    {ok, _Party3} = cb_party:create_party(<<"Bob Smith">>, <<"b1@example.com">>),

    {ok, Duplicates} = cb_party:detect_duplicate_parties(),
    ?assert(length(Duplicates) >= 1),
    ok.

%% Test: Merge party transfers account ownership
merge_party_transfers_accounts(_Config) ->
    {ok, Source} = cb_party:create_party(<<"Merge Source">>, <<"source@example.com">>),
    {ok, Target} = cb_party:create_party(<<"Merge Target">>, <<"target@example.com">>),
    {ok, Account} = cb_accounts:create_account(Source#party.party_id, <<"Main">>, 'USD'),

    {ok, Merged} = cb_party:merge_parties(Source#party.party_id, Target#party.party_id, <<"duplicate_record">>),
    ?assertEqual(closed, Merged#party.status),
    ?assertEqual(Target#party.party_id, Merged#party.merged_into_party_id),

    {ok, TransferredAccount} = cb_accounts:get_account(Account#account.account_id),
    ?assertEqual(Target#party.party_id, TransferredAccount#account.party_id),
    ok.
