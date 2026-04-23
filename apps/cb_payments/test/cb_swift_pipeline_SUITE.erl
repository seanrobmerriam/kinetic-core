-module(cb_swift_pipeline_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([
    receive_mt103_ok/1,
    receive_mx_pain001_ok/1,
    get_message_ok/1,
    get_message_not_found/1,
    list_messages_ok/1,
    list_by_status_ok/1,
    validate_message_ok/1,
    translate_to_payment_order_ok/1
]).

all() ->
    [
        receive_mt103_ok,
        receive_mx_pain001_ok,
        get_message_ok,
        get_message_not_found,
        list_messages_ok,
        list_by_status_ok,
        validate_message_ok,
        translate_to_payment_order_ok
    ].

init_per_suite(Config) ->
    mnesia:start(),
    cb_schema:create_tables(),
    Config.

end_per_suite(_Config) ->
    mnesia:stop(),
    ok.

sample_mt103() ->
    <<":20:REF123456\n"
      ":23B:CRED\n"
      ":32A:230101USD1000,00\n"
      ":50K:SENDERBIC\n"
      ":57A:RECVRBIC\n"
      ":59:/12345678\n"
      "Beneficiary Name\n"
      ":70:Payment for services\n"
      ":71A:SHA\n">>.

sample_mx_pain001() ->
    <<"<Document><CstmrCdtTrfInitn>"
      "<GrpHdr><MsgId>MSG001</MsgId></GrpHdr>"
      "<PmtInf><Dbtr><Nm>Sender</Nm></Dbtr>"
      "<CdtTrfTxInf><Amt><InstdAmt Ccy=\"EUR\">500.00</InstdAmt></Amt>"
      "<Cdtr><Nm>Receiver</Nm></Cdtr></CdtTrfTxInf>"
      "</PmtInf></CstmrCdtTrfInitn></Document>">>.

receive_mt103_ok(_Config) ->
    {ok, MsgId} = cb_swift_pipeline:receive_message(mt103, sample_mt103()),
    ?assert(is_binary(MsgId)).

receive_mx_pain001_ok(_Config) ->
    {ok, MsgId} = cb_swift_pipeline:receive_message(mx_pain001, sample_mx_pain001()),
    ?assert(is_binary(MsgId)).

get_message_ok(_Config) ->
    {ok, MsgId} = cb_swift_pipeline:receive_message(mt103, sample_mt103()),
    {ok, Msg} = cb_swift_pipeline:get_message(MsgId),
    ?assertEqual(MsgId, Msg#swift_message.message_id).

get_message_not_found(_Config) ->
    {error, not_found} = cb_swift_pipeline:get_message(<<"no-such-id">>).

list_messages_ok(_Config) ->
    {ok, _} = cb_swift_pipeline:receive_message(mt103, sample_mt103()),
    All = cb_swift_pipeline:list_messages(),
    ?assert(length(All) >= 1).

list_by_status_ok(_Config) ->
    {ok, _} = cb_swift_pipeline:receive_message(mt103, sample_mt103()),
    Received = cb_swift_pipeline:list_by_status(validated),
    ?assert(is_list(Received)).

validate_message_ok(_Config) ->
    {ok, MsgId} = cb_swift_pipeline:receive_message(mt103, sample_mt103()),
    {ok, Msg}   = cb_swift_pipeline:get_message(MsgId),
    {ok, _Validated} = cb_swift_pipeline:validate_message(Msg).

translate_to_payment_order_ok(_Config) ->
    {ok, MsgId} = cb_swift_pipeline:receive_message(mt103, sample_mt103()),
    {ok, Msg}   = cb_swift_pipeline:get_message(MsgId),
    {ok, Order} = cb_swift_pipeline:to_payment_order(Msg),
    ?assert(is_map(Order)).
