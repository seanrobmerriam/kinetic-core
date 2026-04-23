-module(cb_loan_repayments_handler).

-include_lib("cb_loans/include/loan.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    handle(Method, Req, State).

handle(<<"POST">>, Req, State) ->
    LoanId = cowboy_req:binding(loan_id, Req),
    case LoanId of
        undefined ->
            {Status, ErrorAtom, Message} = cb_http_errors:to_response(missing_required_field),
            Resp = #{error => ErrorAtom, message => Message},
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State};
        _ ->
            record_repayment(LoanId, Req, State)
    end;

handle(<<"GET">>, Req, State) ->
    LoanId = cowboy_req:binding(loan_id, Req),
    case LoanId of
        undefined ->
            {Status, ErrorAtom, Message} = cb_http_errors:to_response(missing_required_field),
            Resp = #{error => ErrorAtom, message => Message},
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State};
        _ ->
            list_repayments(LoanId, Req, State)
    end;

handle(<<"OPTIONS">>, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, Req, State) ->
    {_Code405, _Hdrs405, _Body405} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(_Code405, _Hdrs405, _Body405, Req),
    {ok, Req2, State}.

record_repayment(LoanId, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body) of
        {ok, Json, _} ->
            RequiredFields = [<<"amount">>, <<"payment_type">>],
            case has_all_required_fields(Json, RequiredFields) of
                true ->
                    Amount = maps:get(<<"amount">>, Json),
                    PaymentType = maps:get(<<"payment_type">>, Json),
                    case cb_loan_accounts:get_loan(LoanId) of
                        {ok, Loan} ->
                            case Loan#loan_account.status of
                                disbursed ->
                                    DueDate = calculate_due_date(Loan),
                                    PrincipalPortion = case PaymentType of
                                        <<"full">> -> Loan#loan_account.outstanding_balance;
                                        <<"partial">> -> Amount;
                                        _ -> Amount
                                    end,
                                    case cb_loan_repayments:record_repayment(LoanId, Amount, DueDate, PrincipalPortion) of
                                        {ok, RepaymentId} ->
                                            case cb_loan_accounts:make_repayment(LoanId, Amount) of
                                                {ok, UpdatedLoan, NewBalance} ->
                                                    Resp = #{
                                                        repayment_id => RepaymentId,
                                                        outstanding_balance => NewBalance,
                                                        status => paid,
                                                        loan_status => UpdatedLoan#loan_account.status
                                                    },
                                                    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                                                    Req3 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req2),
                                                    {ok, Req3, State};
                                                {error, Reason} ->
                                                    {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
                                                    Resp = #{error => ErrorAtom, message => Message},
                                                    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                                                    Req3 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req2),
                                                    {ok, Req3, State}
                                            end;
                                        {error, Reason} ->
                                            {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
                                            Resp = #{error => ErrorAtom, message => Message},
                                            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                                            Req3 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req2),
                                            {ok, Req3, State}
                                    end;
                                _OtherStatus ->
                                    {Status, ErrorAtom, Message} = cb_http_errors:to_response(invalid_status),
                                    Resp = #{error => ErrorAtom, message => Message},
                                    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                                    Req3 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req2),
                                    {ok, Req3, State}
                            end;
                        {error, Reason} ->
                            {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
                            Resp = #{error => ErrorAtom, message => Message},
                            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                            Req3 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req2),
                            {ok, Req3, State}
                    end;
                false ->
                    {Status, ErrorAtom, Message} = cb_http_errors:to_response(missing_required_field),
                    Resp = #{error => ErrorAtom, message => Message},
                    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                    Req3 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req2),
                    {ok, Req3, State}
            end;
        _ ->
            {Status, ErrorAtom, Message} = cb_http_errors:to_response(invalid_json),
            Resp = #{error => ErrorAtom, message => Message},
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req3 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req2),
            {ok, Req3, State}
    end.

list_repayments(LoanId, Req, State) ->
    Repayments = cb_loan_repayments:get_repayments(LoanId),
    Resp = #{
        items => [repayment_to_json(R) || R <- Repayments]
    },
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req),
    {ok, Req2, State}.

calculate_due_date(Loan) ->
    DisbursedAt = Loan#loan_account.disbursed_at,
    TermMonths = Loan#loan_account.term_months,
    DisbursedAt + (TermMonths * 30 * 24 * 60 * 60 * 1000).

has_all_required_fields(Json, Fields) ->
    lists:all(fun(Field) -> maps:is_key(Field, Json) end, Fields).

repayment_to_json(Repayment) ->
    #{
        repayment_id => Repayment#loan_repayment.repayment_id,
        loan_id => Repayment#loan_repayment.loan_id,
        amount => Repayment#loan_repayment.amount,
        principal_portion => Repayment#loan_repayment.principal_portion,
        interest_portion => Repayment#loan_repayment.interest_portion,
        penalty => Repayment#loan_repayment.penalty,
        due_date => Repayment#loan_repayment.due_date,
        paid_at => Repayment#loan_repayment.paid_at,
        status => Repayment#loan_repayment.status,
        created_at => Repayment#loan_repayment.created_at
    }.
