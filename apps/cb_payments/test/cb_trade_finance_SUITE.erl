-module(cb_trade_finance_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([
    issue_instrument_ok/1,
    get_instrument_ok/1,
    get_instrument_not_found/1,
    list_instruments_ok/1,
    settle_instrument_ok/1,
    expire_instrument_ok/1,
    cancel_instrument_ok/1,
    add_document_ok/1,
    list_documents_ok/1,
    review_document_compliant/1,
    review_document_discrepant/1
]).

all() ->
    [
        issue_instrument_ok,
        get_instrument_ok,
        get_instrument_not_found,
        list_instruments_ok,
        settle_instrument_ok,
        expire_instrument_ok,
        cancel_instrument_ok,
        add_document_ok,
        list_documents_ok,
        review_document_compliant,
        review_document_discrepant
    ].

init_per_suite(Config) ->
    mnesia:start(),
    cb_schema:create_tables(),
    Config.

end_per_suite(_Config) ->
    mnesia:stop(),
    ok.

issue_instrument_ok(_Config) ->
    {ok, Inst} = cb_trade_finance:issue_instrument(#{
        account_id      => <<"acct-001">>,
        counterparty_id => <<"party-b">>,
        instrument_type => letter_of_credit,
        currency        => 'USD',
        face_amount     => 500000,
        expiry_date     => 20261231
    }),
    ?assert(is_binary(Inst#trade_instrument.instrument_id)),
    ?assertEqual(issued, Inst#trade_instrument.status).

get_instrument_ok(_Config) ->
    {ok, Inst} = cb_trade_finance:issue_instrument(#{
        account_id      => <<"acct-002">>,
        counterparty_id => <<"party-d">>,
        instrument_type => guarantee,
        currency        => 'EUR',
        face_amount     => 200000,
        expiry_date     => 20270101
    }),
    {ok, Got} = cb_trade_finance:get_instrument(Inst#trade_instrument.instrument_id),
    ?assertEqual(Inst#trade_instrument.instrument_id, Got#trade_instrument.instrument_id).

get_instrument_not_found(_Config) ->
    {error, not_found} = cb_trade_finance:get_instrument(<<"no-such">>).

list_instruments_ok(_Config) ->
    AccountId = <<"acct-list">>,
    {ok, _} = cb_trade_finance:issue_instrument(#{
        account_id => AccountId, counterparty_id => <<"b">>,
        instrument_type => standby_lc, currency => 'USD',
        face_amount => 100, expiry_date => 20280101
    }),
    Insts = cb_trade_finance:list_instruments(AccountId),
    ?assert(length(Insts) >= 1).

settle_instrument_ok(_Config) ->
    {ok, Inst} = cb_trade_finance:issue_instrument(#{
        account_id => <<"acct-s1">>, counterparty_id => <<"p2">>,
        instrument_type => letter_of_credit, currency => 'USD',
        face_amount => 10000, expiry_date => 20290101
    }),
    ok = cb_trade_finance:settle_instrument(Inst#trade_instrument.instrument_id),
    {ok, Updated} = cb_trade_finance:get_instrument(Inst#trade_instrument.instrument_id),
    ?assertEqual(settled, Updated#trade_instrument.status).

expire_instrument_ok(_Config) ->
    {ok, Inst} = cb_trade_finance:issue_instrument(#{
        account_id => <<"acct-e1">>, counterparty_id => <<"p4">>,
        instrument_type => guarantee, currency => 'EUR',
        face_amount => 5000, expiry_date => 20200101
    }),
    ok = cb_trade_finance:expire_instrument(Inst#trade_instrument.instrument_id),
    {ok, Updated} = cb_trade_finance:get_instrument(Inst#trade_instrument.instrument_id),
    ?assertEqual(expired, Updated#trade_instrument.status).

cancel_instrument_ok(_Config) ->
    {ok, Inst} = cb_trade_finance:issue_instrument(#{
        account_id => <<"acct-c1">>, counterparty_id => <<"p6">>,
        instrument_type => standby_lc, currency => 'USD',
        face_amount => 7500, expiry_date => 20300101
    }),
    ok = cb_trade_finance:cancel_instrument(Inst#trade_instrument.instrument_id),
    {ok, Updated} = cb_trade_finance:get_instrument(Inst#trade_instrument.instrument_id),
    ?assertEqual(cancelled, Updated#trade_instrument.status).

add_document_ok(_Config) ->
    {ok, Inst} = cb_trade_finance:issue_instrument(#{
        account_id => <<"acct-d1">>, counterparty_id => <<"p8">>,
        instrument_type => letter_of_credit, currency => 'USD',
        face_amount => 25000, expiry_date => 20310101
    }),
    {ok, Doc} = cb_trade_finance:add_document(Inst#trade_instrument.instrument_id, #{
        document_type => <<"bill_of_lading">>
    }),
    ?assert(is_binary(Doc#trade_document.document_id)),
    ?assertEqual(pending, Doc#trade_document.status).

list_documents_ok(_Config) ->
    {ok, Inst} = cb_trade_finance:issue_instrument(#{
        account_id => <<"acct-d2">>, counterparty_id => <<"p10">>,
        instrument_type => guarantee, currency => 'EUR',
        face_amount => 15000, expiry_date => 20320101
    }),
    {ok, _} = cb_trade_finance:add_document(Inst#trade_instrument.instrument_id, #{
        document_type => <<"invoice">>
    }),
    Docs = cb_trade_finance:list_documents(Inst#trade_instrument.instrument_id),
    ?assert(length(Docs) >= 1).

review_document_compliant(_Config) ->
    {ok, Inst} = cb_trade_finance:issue_instrument(#{
        account_id => <<"acct-rv1">>, counterparty_id => <<"p12">>,
        instrument_type => letter_of_credit, currency => 'USD',
        face_amount => 8000, expiry_date => 20330101
    }),
    {ok, Doc} = cb_trade_finance:add_document(Inst#trade_instrument.instrument_id, #{
        document_type => <<"certificate">>
    }),
    {ok, Reviewed} = cb_trade_finance:review_document(
        Doc#trade_document.document_id, compliant, []
    ),
    ?assertEqual(compliant, Reviewed#trade_document.status).

review_document_discrepant(_Config) ->
    {ok, Inst} = cb_trade_finance:issue_instrument(#{
        account_id => <<"acct-rv2">>, counterparty_id => <<"p14">>,
        instrument_type => guarantee, currency => 'EUR',
        face_amount => 3000, expiry_date => 20340101
    }),
    {ok, Doc} = cb_trade_finance:add_document(Inst#trade_instrument.instrument_id, #{
        document_type => <<"packing_list">>
    }),
    {ok, Reviewed} = cb_trade_finance:review_document(
        Doc#trade_document.document_id, discrepant, [<<"qty mismatch">>]
    ),
    ?assertEqual(discrepant, Reviewed#trade_document.status).
