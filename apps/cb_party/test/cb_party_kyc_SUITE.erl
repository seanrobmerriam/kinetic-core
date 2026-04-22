-module(cb_party_kyc_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    kyc_initial_status/1,
    kyc_update_to_pending/1,
    kyc_update_to_approved/1,
    kyc_update_to_rejected_with_notes/1,
    kyc_invalid_status_rejected/1,
    onboarding_update_complete/1,
    onboarding_update_incomplete/1,
    add_doc_ref/1,
    add_multiple_doc_refs/1,
    risk_tier_default_low/1,
    risk_tier_set_low/1,
    risk_tier_set_high/1,
    risk_tier_invalid/1,
    retention_days_for_tiers/1
]).

all() ->
    [
        kyc_initial_status,
        kyc_update_to_pending,
        kyc_update_to_approved,
        kyc_update_to_rejected_with_notes,
        kyc_invalid_status_rejected,
        onboarding_update_complete,
        onboarding_update_incomplete,
        add_doc_ref,
        add_multiple_doc_refs,
        risk_tier_default_low,
        risk_tier_set_low,
        risk_tier_set_high,
        risk_tier_invalid,
        retention_days_for_tiers
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
    lists:foreach(fun(T) -> mnesia:clear_table(T) end,
                  [party, account, transaction, ledger_entry]),
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

%% New parties start with not_started KYC and incomplete onboarding
kyc_initial_status(_Config) ->
    {ok, Party} = cb_party:create_party(<<"Alice Test">>, <<"alice_kyc@example.com">>),
    ?assertEqual(not_started, Party#party.kyc_status),
    ?assertEqual(incomplete, Party#party.onboarding_status),
    ?assertEqual(undefined, Party#party.review_notes),
    ?assertEqual([], Party#party.doc_refs),
    ok.

%% Update KYC status to pending
kyc_update_to_pending(_Config) ->
    {ok, Party} = cb_party:create_party(<<"Bob Test">>, <<"bob_kyc@example.com">>),
    {ok, Updated} = cb_party:update_kyc_status(Party#party.party_id, pending, undefined),
    ?assertEqual(pending, Updated#party.kyc_status),
    ok.

%% Update KYC status through to approved
kyc_update_to_approved(_Config) ->
    {ok, Party} = cb_party:create_party(<<"Carol Test">>, <<"carol_kyc@example.com">>),
    {ok, P2} = cb_party:update_kyc_status(Party#party.party_id, pending, undefined),
    ?assertEqual(pending, P2#party.kyc_status),
    {ok, P3} = cb_party:update_kyc_status(P2#party.party_id, approved, <<"Documents verified">>),
    ?assertEqual(approved, P3#party.kyc_status),
    ?assertEqual(<<"Documents verified">>, P3#party.review_notes),
    ok.

%% Reject KYC with mandatory notes
kyc_update_to_rejected_with_notes(_Config) ->
    {ok, Party} = cb_party:create_party(<<"Dan Test">>, <<"dan_kyc@example.com">>),
    Notes = <<"ID document expired">>,
    {ok, Updated} = cb_party:update_kyc_status(Party#party.party_id, rejected, Notes),
    ?assertEqual(rejected, Updated#party.kyc_status),
    ?assertEqual(Notes, Updated#party.review_notes),
    ok.

%% Invalid KYC status atom is rejected
kyc_invalid_status_rejected(_Config) ->
    {ok, Party} = cb_party:create_party(<<"Eve Test">>, <<"eve_kyc@example.com">>),
    Result = cb_party:update_kyc_status(Party#party.party_id, unknown_status, undefined),
    ?assertEqual({error, invalid_kyc_status}, Result),
    ok.

%% Update onboarding status to complete
onboarding_update_complete(_Config) ->
    {ok, Party} = cb_party:create_party(<<"Frank Test">>, <<"frank_kyc@example.com">>),
    {ok, Updated} = cb_party:update_onboarding_status(Party#party.party_id, complete),
    ?assertEqual(complete, Updated#party.onboarding_status),
    ok.

%% Update onboarding status back to incomplete
onboarding_update_incomplete(_Config) ->
    {ok, Party} = cb_party:create_party(<<"Grace Test">>, <<"grace_kyc@example.com">>),
    {ok, P2} = cb_party:update_onboarding_status(Party#party.party_id, complete),
    ?assertEqual(complete, P2#party.onboarding_status),
    {ok, P3} = cb_party:update_onboarding_status(P2#party.party_id, incomplete),
    ?assertEqual(incomplete, P3#party.onboarding_status),
    ok.

%% Add a document reference to a party
add_doc_ref(_Config) ->
    {ok, Party} = cb_party:create_party(<<"Henry Test">>, <<"henry_kyc@example.com">>),
    DocRef = <<"s3://docs/passport-henry.jpg">>,
    {ok, Updated} = cb_party:add_doc_ref(Party#party.party_id, DocRef),
    ?assert(lists:member(DocRef, Updated#party.doc_refs)),
    ok.

%% Multiple document references accumulate
add_multiple_doc_refs(_Config) ->
    {ok, Party} = cb_party:create_party(<<"Iris Test">>, <<"iris_kyc@example.com">>),
    {ok, P2} = cb_party:add_doc_ref(Party#party.party_id, <<"s3://docs/passport.jpg">>),
    {ok, P3} = cb_party:add_doc_ref(P2#party.party_id, <<"s3://docs/utility-bill.pdf">>),
    ?assertEqual(2, length(P3#party.doc_refs)),
    ok.

%% New parties default to low risk tier
risk_tier_default_low(_Config) ->
    {ok, Party} = cb_party:create_party(<<"RT Default">>, <<"rt_default@example.com">>),
    ?assertEqual(low, Party#party.risk_tier),
    ok.

%% Can set risk tier to low
risk_tier_set_low(_Config) ->
    {ok, Party} = cb_party:create_party(<<"RT Low">>, <<"rt_low@example.com">>),
    {ok, Updated} = cb_party:set_risk_tier(Party#party.party_id, low),
    ?assertEqual(low, Updated#party.risk_tier),
    ok.

%% Can set risk tier to high
risk_tier_set_high(_Config) ->
    {ok, Party} = cb_party:create_party(<<"RT High">>, <<"rt_high@example.com">>),
    {ok, Updated} = cb_party:set_risk_tier(Party#party.party_id, high),
    ?assertEqual(high, Updated#party.risk_tier),
    ok.

%% Invalid tier atom returns error
risk_tier_invalid(_Config) ->
    {ok, Party} = cb_party:create_party(<<"RT Invalid">>, <<"rt_invalid@example.com">>),
    {error, invalid_risk_tier} = cb_party:set_risk_tier(Party#party.party_id, extreme),
    ok.

%% Retention days are correct for all tiers
retention_days_for_tiers(_Config) ->
    ?assertEqual(365,  cb_party:retention_days_for_tier(low)),
    ?assertEqual(730,  cb_party:retention_days_for_tier(medium)),
    ?assertEqual(1825, cb_party:retention_days_for_tier(high)),
    ?assertEqual(3650, cb_party:retention_days_for_tier(critical)),
    ok.
