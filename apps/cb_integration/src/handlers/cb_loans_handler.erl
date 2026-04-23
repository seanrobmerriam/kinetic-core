%% @doc Loans Handler
%%
%% Handler for the `/api/v1/loans` and `/api/v1/loans/:loan_id` endpoints.
%% This is a comprehensive handler that manages the complete loan lifecycle.
%%
%% <h2>Loan Lifecycle</h2>
%%
%% <ol>
%%   <li><b>Created</b> - Loan application submitted with product, principal, term</li>
%%   <li><b>Approved</b> - Loan approved by system or manually</li>
%%   <li><b>Disbursed</b> - Funds transferred to borrower account</li>
%%   <li><b>Repaying</b> - Borrower makes regular payments</li>
%%   <li><b>Paid Off</b> - All payments complete</li>
%% </ol>
%%
%% <h2>REST API Endpoints</h2>
%%
%% <ul>
%%   <li><b>POST /api/v1/loans</b> - Create a new loan application</li>
%%   <li><b>GET /api/v1/loans</b> - List loans for a party</li>
%%   <li><b>GET /api/v1/loans/:loan_id</b> - Get loan details</li>
%%   <li><b>POST /api/v1/loans/:loan_id/approve</b> - Approve a loan</li>
%%   <li><b>POST /api/v1/loans/:loan_id/disburse</b> - Disburse loan funds</li>
%% </ul>
%%
%% <h2>Creating a Loan (POST /api/v1/loans)</h2>
%%
%% Required fields:
%% <ul>
%%   <li><code>party_id</code> - UUID of the borrowing party</li>
%%   <li><code>product_id</code> - UUID of the loan product</li>
%%   <li><code>account_id</code> - Destination account for disbursement</li>
%%   <li><code>principal</code> - Loan amount in minor units</li>
%%   <li><code>term_months</code> - Loan term in months</li>
%% </ul>
%%
%% <h2>Loan States</h2>
%%
%% <ul>
%%   <li><code>pending</code> - Awaiting approval</li>
%%   <li><code>approved</code> - Approved, awaiting disbursement</li>
%%   <li><code>active</code> - Disbursed and being repaid</li>
%%   <li><code>paid_off</code> - Fully repaid</li>
%%   <li><code>defaulted</code> - Payment failure</li>
%% </ul>
%%
%% @see cb_loan_accounts
%% @see cb_loan_products
-module(cb_loans_handler).

-include_lib("cb_loans/include/loan.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    handle(Method, Req, State).

handle(<<"POST">>, Req, State) ->
    Path = cowboy_req:path(Req),
    case cowboy_req:binding(loan_id, Req) of
        undefined ->
            create_loan(Req, State);
        LoanId when is_binary(LoanId) ->
            case Path of
                <<"/api/v1/loans/", _/binary>> ->
                    case binary:split(Path, <<"/">>, [global]) of
                        [_, <<"api">>, <<"v1">>, <<"loans">>, LoanId, Action] ->
                            case Action of
                                <<"approve">> -> approve_loan(LoanId, Req, State);
                                <<"disburse">> -> disburse_loan(LoanId, Req, State);
                                _ ->
                                    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                                    Req2 = cowboy_req:reply(404, Headers, <<"{\"error\": \"not_found\"}">>, Req),
                                    {ok, Req2, State}
                            end;
                        _ ->
                            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                            Req2 = cowboy_req:reply(404, Headers, <<"{\"error\": \"not_found\"}">>, Req),
                            {ok, Req2, State}
                    end;
                _ ->
                    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                    Req2 = cowboy_req:reply(404, Headers, <<"{\"error\": \"not_found\"}">>, Req),
                    {ok, Req2, State}
            end
    end;

handle(<<"GET">>, Req, State) ->
    case cowboy_req:binding(loan_id, Req) of
        undefined ->
            list_loans(Req, State);
        LoanId ->
            get_loan(LoanId, Req, State)
    end;

handle(<<"OPTIONS">>, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, Req, State) ->
    {_Code405, _Hdrs405, _Body405} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(_Code405, _Hdrs405, _Body405, Req),
    {ok, Req2, State}.

create_loan(Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body) of
        {ok, Json, _} ->
            RequiredFields = [<<"party_id">>, <<"product_id">>, <<"account_id">>, <<"principal">>, <<"term_months">>],
            case has_all_required_fields(Json, RequiredFields) of
                true ->
                    PartyId = maps:get(<<"party_id">>, Json),
                    ProductId = maps:get(<<"product_id">>, Json),
                    AccountId = maps:get(<<"account_id">>, Json),
                    Principal = maps:get(<<"principal">>, Json),
                    TermMonths = maps:get(<<"term_months">>, Json),
                    case cb_loan_products:get_product(ProductId) of
                        {ok, Product} ->
                            Currency = Product#loan_product.currency,
                            InterestRate = Product#loan_product.interest_rate,
                            case cb_loan_accounts:create_loan(ProductId, PartyId, AccountId, Principal, Currency, TermMonths, InterestRate) of
                                {ok, LoanId} ->
                                    Resp = #{loan_id => LoanId},
                                    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
                                    Req3 = cowboy_req:reply(201, Headers, jsone:encode(Resp), Req2),
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

list_loans(Req, State) ->
    Qs = cowboy_req:parse_qs(Req),
    PartyId = proplists:get_value(<<"party_id">>, Qs),
    case PartyId of
        undefined ->
            {Status, ErrorAtom, Message} = cb_http_errors:to_response(missing_required_field),
            Resp = #{error => ErrorAtom, message => Message},
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State};
        _ ->
            Loans = cb_loan_accounts:list_loans(PartyId),
            Resp = #{
                items => [loan_to_json(L) || L <- Loans]
            },
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State}
    end.

get_loan(LoanId, Req, State) ->
    case cb_loan_accounts:get_loan(LoanId) of
        {ok, Loan} ->
            Resp = loan_to_json(Loan),
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State};
        {error, Reason} ->
            {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
            Resp = #{error => ErrorAtom, message => Message},
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State}
    end.

approve_loan(LoanId, Req, State) ->
    case cb_loan_accounts:approve_loan(LoanId) of
        {ok, Loan} ->
            Resp = loan_to_json(Loan),
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State};
        {error, Reason} ->
            {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
            Resp = #{error => ErrorAtom, message => Message},
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State}
    end.

disburse_loan(LoanId, Req, State) ->
    case cb_loan_accounts:disburse_loan(LoanId) of
        {ok, Loan} ->
            Resp = loan_to_json(Loan),
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(200, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State};
        {error, Reason} ->
            {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
            Resp = #{error => ErrorAtom, message => Message},
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State}
    end.

has_all_required_fields(Json, Fields) ->
    lists:all(fun(Field) -> maps:is_key(Field, Json) end, Fields).

loan_to_json(Loan) ->
    #{
        loan_id => Loan#loan_account.loan_id,
        product_id => Loan#loan_account.product_id,
        party_id => Loan#loan_account.party_id,
        account_id => Loan#loan_account.account_id,
        principal => Loan#loan_account.principal,
        currency => Loan#loan_account.currency,
        interest_rate_bps => Loan#loan_account.interest_rate,
        term_months => Loan#loan_account.term_months,
        monthly_payment => Loan#loan_account.monthly_payment,
        outstanding_balance => Loan#loan_account.outstanding_balance,
        status => Loan#loan_account.status,
        disbursed_at => Loan#loan_account.disbursed_at,
        created_at => Loan#loan_account.created_at,
        updated_at => Loan#loan_account.updated_at
    }.
