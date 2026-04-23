%% @doc ATM Interface Baseline Handler
%%
%% Minimal ATM-channel HTTP handlers for balance inquiry and cash withdrawal.
%%
%% These endpoints model the ATM interaction pattern:
%% - An ATM submits a POST with account identifier and optional PIN metadata.
%% - Inquiry returns current balance and the 5 most recent transactions.
%% - Withdrawal validates against ATM channel limits then delegates to the
%%   core transaction engine with channel=atm stamped on the entry.
%%
%% Authentication is carrier-level (Bearer token for the ATM service account).
%%
%% <h2>REST API Endpoints</h2>
%%
%% <ul>
%%   <li><b>POST /api/v1/atm/inquiry</b> - Balance + recent transaction summary</li>
%%   <li><b>POST /api/v1/atm/withdraw</b> - Cash withdrawal (ATM-limited)</li>
%%   <li><b>OPTIONS</b> - CORS preflight</li>
%% </ul>
%%
%% <h2>POST /api/v1/atm/inquiry</h2>
%%
%% Request body:
%% <pre>{ "account_id": "&lt;uuid&gt;" }</pre>
%%
%% Response body:
%% <pre>
%% {
%%   "account_id": "...",
%%   "balance": 150000,
%%   "currency": "USD",
%%   "recent_transactions": [...]
%% }
%% </pre>
%%
%% <h2>POST /api/v1/atm/withdraw</h2>
%%
%% Request body:
%% <pre>
%% {
%%   "account_id":  "&lt;uuid&gt;",
%%   "amount":      50000,
%%   "currency":    "USD",
%%   "description": "ATM cash withdrawal"
%% }
%% </pre>
-module(cb_atm_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-define(ATM_RECENT_LIMIT, 5).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    Path   = cowboy_req:path(Req),
    handle(Method, Path, Req, State).

handle(<<"POST">>, <<"/api/v1/atm/inquiry">>,  Req, State) -> do_inquiry(Req, State);
handle(<<"POST">>, <<"/api/v1/atm/withdraw">>, Req, State) -> do_withdraw(Req, State);

handle(<<"OPTIONS">>, _, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _, Req, State) ->
    {_Code405, _Hdrs405, _Body405} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(_Code405, _Hdrs405, _Body405, Req),
    {ok, Req2, State}.

%% Inquiry — balance + recent transactions

do_inquiry(Req, State) ->
    case read_json_body(Req) of
        {ok, Body, Req2} ->
            AccountId = maps:get(<<"account_id">>, Body, undefined),
            case cb_accounts:get_account(AccountId) of
                {error, Reason} ->
                    error_reply(Reason, Req2, State);
                {ok, Account} ->
                    RecentTxns = recent_transactions(AccountId, ?ATM_RECENT_LIMIT),
                    Resp = #{
                        account_id           => Account#account.account_id,
                        balance              => Account#account.balance,
                        currency             => Account#account.currency,
                        recent_transactions  => [txn_to_json(T) || T <- RecentTxns]
                    },
                    json_reply(200, Resp, Req2, State)
            end;
        {error, Req2} ->
            error_reply(missing_required_field, Req2, State)
    end.

%% Withdrawal — validates channel limits then executes

do_withdraw(Req, State) ->
    case read_json_body(Req) of
        {ok, Body, Req2} ->
            AccountId   = maps:get(<<"account_id">>,  Body, undefined),
            Amount      = maps:get(<<"amount">>,      Body, undefined),
            CurrencyBin = maps:get(<<"currency">>,    Body, undefined),
            Description = maps:get(<<"description">>, Body, <<"ATM cash withdrawal">>),
            case validate_withdraw_params(AccountId, Amount, CurrencyBin) of
                {error, Reason} ->
                    error_reply(Reason, Req2, State);
                {ok, ValidAmount, Currency} ->
                    case cb_channel_limits:validate_amount(atm, Currency, ValidAmount) of
                        {error, _LimitReason} ->
                            error_reply(limit_exceeded, Req2, State);
                        ok ->
                            IdempKey = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
                            case cb_payments:withdraw(IdempKey, AccountId, ValidAmount, Currency, Description) of
                                {ok, Txn} ->
                                    json_reply(201, txn_to_json(Txn), Req2, State);
                                {error, Reason} ->
                                    error_reply(Reason, Req2, State)
                            end
                    end
            end;
        {error, Req2} ->
            error_reply(missing_required_field, Req2, State)
    end.

%% Internal helpers

recent_transactions(AccountId, Limit) ->
    Debits  = mnesia:dirty_index_read(transaction, AccountId, source_account_id),
    Credits = mnesia:dirty_index_read(transaction, AccountId, dest_account_id),
    All = lists:usort(fun(A, B) ->
        A#transaction.txn_id =< B#transaction.txn_id
    end, Debits ++ Credits),
    Sorted = lists:sort(fun(A, B) ->
        A#transaction.created_at >= B#transaction.created_at
    end, All),
    lists:sublist(Sorted, Limit).

validate_withdraw_params(undefined, _, _) -> {error, missing_required_field};
validate_withdraw_params(_, undefined, _) -> {error, missing_required_field};
validate_withdraw_params(_, _, undefined) -> {error, missing_required_field};
validate_withdraw_params(_, Amount, _) when not is_integer(Amount); Amount =< 0 ->
    {error, invalid_amount};
validate_withdraw_params(_, Amount, CurrencyBin) ->
    case parse_currency(CurrencyBin) of
        {ok, Currency} -> {ok, Amount, Currency};
        {error, _}     -> {error, invalid_currency}
    end.

parse_currency(<<"USD">>) -> {ok, 'USD'};
parse_currency(<<"EUR">>) -> {ok, 'EUR'};
parse_currency(<<"GBP">>) -> {ok, 'GBP'};
parse_currency(<<"JPY">>) -> {ok, 'JPY'};
parse_currency(<<"CHF">>) -> {ok, 'CHF'};
parse_currency(<<"AUD">>) -> {ok, 'AUD'};
parse_currency(<<"CAD">>) -> {ok, 'CAD'};
parse_currency(<<"SGD">>) -> {ok, 'SGD'};
parse_currency(<<"HKD">>) -> {ok, 'HKD'};
parse_currency(<<"NZD">>) -> {ok, 'NZD'};
parse_currency(_)         -> {error, invalid_currency}.

txn_to_json(T) ->
    #{
        txn_id     => T#transaction.txn_id,
        txn_type   => T#transaction.txn_type,
        status     => T#transaction.status,
        amount     => T#transaction.amount,
        currency   => T#transaction.currency,
        channel    => null_or_val(T#transaction.channel),
        created_at => T#transaction.created_at
    }.

null_or_val(undefined) -> null;
null_or_val(Val)        -> Val.

json_reply(Status, Body, Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Body), Req),
    {ok, Req2, State}.

error_reply(Reason, Req, State) ->
    {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
    Resp = #{error => ErrorAtom, message => Message},
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
    {ok, Req2, State}.

read_json_body(Req) ->
    case cowboy_req:read_body(Req) of
        {ok, Body, Req2} ->
            case jsone:try_decode(Body) of
                {ok, Decoded, _} when is_map(Decoded) -> {ok, Decoded, Req2};
                _                                      -> {error, Req2}
            end;
        _ ->
            {error, Req}
    end.
