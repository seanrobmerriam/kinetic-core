%% @doc HTTP handler for SWIFT/ISO 20022 message pipeline (TASK-060).
%%
%% Routes:
%%   GET  /api/v1/payments/swift                    — list all messages
%%   POST /api/v1/payments/swift                    — receive a new message
%%   GET  /api/v1/payments/swift/:message_id        — get message by ID
%%   GET  /api/v1/payments/swift/status/:status     — list messages by status
%%   POST /api/v1/payments/swift/:message_id/translate — translate to payment order
-module(cb_swift_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

init(Req, State) ->
    Method    = cowboy_req:method(Req),
    MessageId = cowboy_req:binding(message_id, Req),
    Action    = cowboy_req:binding(action, Req),
    handle(Method, MessageId, Action, Req, State).

handle(<<"GET">>, undefined, undefined, Req, State) ->
    Messages = cb_swift_pipeline:list_messages(),
    Req2 = cowboy_req:reply(200, headers(),
               jsone:encode(#{messages => [message_to_map(M) || M <- Messages]}), Req),
    {ok, Req2, State};

handle(<<"POST">>, undefined, undefined, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{message_type := TypeBin, payload := Payload}, _} ->
            MsgType = parse_message_type(TypeBin),
            case cb_swift_pipeline:receive_message(MsgType, Payload) of
                {ok, MessageId} ->
                    Req3 = cowboy_req:reply(201, headers(),
                               jsone:encode(#{message_id => MessageId}), Req2),
                    {ok, Req3, State};
                {error, Reason} ->
                    error_reply(422, Reason, Req2, State)
            end;
        _ ->
            error_reply(400, <<"Missing required fields: message_type, payload">>, Req2, State)
    end;

handle(<<"GET">>, <<"status">>, Status, Req, State) ->
    StatusAtom = binary_to_existing_atom(Status, utf8),
    Messages   = cb_swift_pipeline:list_by_status(StatusAtom),
    Req2 = cowboy_req:reply(200, headers(),
               jsone:encode(#{messages => [message_to_map(M) || M <- Messages]}), Req),
    {ok, Req2, State};

handle(<<"GET">>, MessageId, undefined, Req, State) ->
    case cb_swift_pipeline:get_message(MessageId) of
        {ok, Msg} ->
            Req2 = cowboy_req:reply(200, headers(), jsone:encode(message_to_map(Msg)), Req),
            {ok, Req2, State};
        {error, not_found} ->
            error_reply(404, <<"Message not found">>, Req, State)
    end;

handle(<<"POST">>, MessageId, <<"translate">>, Req, State) ->
    case cb_swift_pipeline:get_message(MessageId) of
        {ok, Msg} ->
            case cb_swift_pipeline:to_payment_order(Msg) of
                {ok, Order} ->
                    Req2 = cowboy_req:reply(200, headers(),
                               jsone:encode(#{payment_order => Order}), Req),
                    {ok, Req2, State};
                {error, Reason} ->
                    error_reply(422, Reason, Req, State)
            end;
        {error, not_found} ->
            error_reply(404, <<"Message not found">>, Req, State)
    end;

handle(_Method, _MessageId, _Action, Req, State) ->
    error_reply(405, <<"Method not allowed">>, Req, State).

%%--------------------------------------------------------------------
%% Helpers
%%--------------------------------------------------------------------

parse_message_type(<<"mt103">>)      -> mt103;
parse_message_type(<<"mt202">>)      -> mt202;
parse_message_type(<<"mx_pain001">>) -> mx_pain001;
parse_message_type(<<"mx_camt053">>) -> mx_camt053;
parse_message_type(_)                -> mt103.

message_to_map(M) ->
    #{message_id      => M#swift_message.message_id,
      message_type    => M#swift_message.message_type,
      sender_bic      => M#swift_message.sender_bic,
      receiver_bic    => M#swift_message.receiver_bic,
      reference       => M#swift_message.reference,
      amount          => M#swift_message.amount,
      currency        => M#swift_message.currency,
      status          => M#swift_message.status,
      rejection_reason => M#swift_message.rejection_reason,
      payment_id      => M#swift_message.payment_id,
      received_at     => M#swift_message.received_at}.

headers() ->
    #{<<"content-type">> => <<"application/json">>}.

error_reply(Code, Reason, Req, State) when is_atom(Reason) ->
    error_reply(Code, atom_to_binary(Reason, utf8), Req, State);
error_reply(Code, Reason, Req, State) ->
    Req2 = cowboy_req:reply(Code, headers(),
               jsone:encode(#{error => Reason}), Req),
    {ok, Req2, State}.
