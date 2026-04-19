%% @doc Development mock data importer.
%%
%% Builds a deterministic demo dataset and is safe to run repeatedly.

-module(cb_mock_data_importer).

-include_lib("cb_ledger/include/cb_ledger.hrl").
-include_lib("cb_loans/include/loan.hrl").

-export([import/0]).

-type summary() :: #{atom() => non_neg_integer()}.

-spec import() -> {ok, summary()} | {error, term()}.
import() ->
    Summary0 = new_summary(),
    with_import_lock(fun() ->
        do_import(Summary0)
    end).

do_import(Summary0) ->
    {ok, AliceMainId, Summary1} = ensure_party_account(
        <<"Alice Chen">>, <<"alice.mock@ironledger.dev">>, <<"Alice Main Checking">>, 'USD', Summary0
    ),
    {ok, AliceSavingsId, Summary2} = ensure_party_account(
        <<"Alice Chen">>, <<"alice.mock@ironledger.dev">>, <<"Alice Savings Reserve">>, 'USD', Summary1
    ),
    {ok, BobMainId, Summary3} = ensure_party_account(
        <<"Bob Smith">>, <<"bob.mock@ironledger.dev">>, <<"Bob Main Checking">>, 'USD', Summary2
    ),
    {ok, _CarolMainId, Summary4} = ensure_party_account(
        <<"Carol Diaz">>, <<"carol.mock@ironledger.dev">>, <<"Carol Main Checking">>, 'USD', Summary3
    ),
    {ok, _DaveMainId, Summary5} = ensure_party_account(
        <<"Dave Patel">>, <<"dave.mock@ironledger.dev">>, <<"Dave Main Checking">>, 'EUR', Summary4
    ),

    {ok, _GrowthSavingsProductId, Summary6} = ensure_savings_product(
        <<"Growth Saver">>,
        <<"Demo high-yield savings product">>,
        'USD',
        425,
        compound,
        monthly,
        10000,
        Summary5
    ),
    {ok, _StarterSavingsProductId, Summary7} = ensure_savings_product(
        <<"Starter Saver">>,
        <<"Demo starter savings product">>,
        'USD',
        150,
        simple,
        monthly,
        0,
        Summary6
    ),
    {ok, LoanProductId, Summary8} = ensure_loan_product(
        <<"Personal Flex Loan">>,
        <<"Demo unsecured personal loan">>,
        'USD',
        50000,
        2000000,
        6,
        60,
        850,
        declining,
        Summary7
    ),

    {ok, Summary9} = ensure_payment_txn(
        <<"mock-deposit-alice-main-v1">>,
        fun() -> cb_payments:deposit(<<"mock-deposit-alice-main-v1">>, AliceMainId, 250000, 'USD', <<"Initial funding">>) end,
        Summary8
    ),
    {ok, Summary10} = ensure_payment_txn(
        <<"mock-deposit-alice-savings-v1">>,
        fun() -> cb_payments:deposit(<<"mock-deposit-alice-savings-v1">>, AliceSavingsId, 900000, 'USD', <<"Savings seed">>) end,
        Summary9
    ),
    {ok, Summary11} = ensure_payment_txn(
        <<"mock-deposit-bob-main-v1">>,
        fun() -> cb_payments:deposit(<<"mock-deposit-bob-main-v1">>, BobMainId, 180000, 'USD', <<"Payroll credit">>) end,
        Summary10
    ),
    {ok, Summary12} = ensure_payment_txn(
        <<"mock-transfer-alice-to-bob-v1">>,
        fun() -> cb_payments:transfer(<<"mock-transfer-alice-to-bob-v1">>, AliceMainId, BobMainId, 35000, 'USD', <<"Shared expenses">>) end,
        Summary11
    ),
    {ok, Summary13} = ensure_payment_txn(
        <<"mock-withdraw-bob-main-v1">>,
        fun() -> cb_payments:withdraw(<<"mock-withdraw-bob-main-v1">>, BobMainId, 12000, 'USD', <<"ATM withdrawal">>) end,
        Summary12
    ),

    {ok, Summary14} = ensure_hold(AliceMainId, 15000, <<"Card authorization demo">>, Summary13),

    {ok, AlicePartyId} = find_party_id_by_email(<<"alice.mock@ironledger.dev">>),
    {ok, Summary15} = ensure_loan_with_repayment(
        LoanProductId,
        AlicePartyId,
        AliceMainId,
        300000,
        'USD',
        24,
        850,
        25000,
        Summary14
    ),

    {ok, Summary15}.

with_import_lock(Fun) ->
    LockKey = {cb_mock_data_importer, import},
    global:trans(LockKey, Fun, [node()]).

new_summary() ->
    #{
        parties_created => 0,
        parties_existing => 0,
        accounts_created => 0,
        accounts_existing => 0,
        savings_products_created => 0,
        savings_products_existing => 0,
        loan_products_created => 0,
        loan_products_existing => 0,
        transactions_created => 0,
        transactions_existing => 0,
        holds_created => 0,
        holds_existing => 0,
        loans_created => 0,
        loans_existing => 0,
        loan_repayments_created => 0,
        loan_repayments_existing => 0
    }.

inc(Key, Summary) ->
    Summary#{Key := maps:get(Key, Summary, 0) + 1}.

ensure_party_account(FullName, Email, AccountName, Currency, Summary0) ->
    case ensure_party(FullName, Email, Summary0) of
        {ok, PartyId, Summary1} ->
            ensure_account(PartyId, AccountName, Currency, Summary1);
        Error ->
            Error
    end.

ensure_party(FullName, Email, Summary0) ->
    case find_party_by_email(Email) of
        {ok, Party} ->
            {ok, Party#party.party_id, inc(parties_existing, Summary0)};
        not_found ->
            case cb_party:create_party(FullName, Email) of
                {ok, Party} ->
                    {ok, Party#party.party_id, inc(parties_created, Summary0)};
                {error, email_already_exists} ->
                    case find_party_by_email(Email) of
                        {ok, Existing} ->
                            {ok, Existing#party.party_id, inc(parties_existing, Summary0)};
                        not_found ->
                            {error, email_already_exists}
                    end;
                {error, Reason} ->
                    {error, Reason}
            end
    end.

ensure_account(PartyId, Name, Currency, Summary0) ->
    case find_account(PartyId, Name, Currency) of
        {ok, Account} ->
            {ok, Account#account.account_id, inc(accounts_existing, Summary0)};
        not_found ->
            case cb_accounts:create_account(PartyId, Name, Currency) of
                {ok, Account} ->
                    {ok, Account#account.account_id, inc(accounts_created, Summary0)};
                {error, Reason} ->
                    {error, Reason}
            end
    end.

ensure_savings_product(Name, Description, Currency, InterestRate, InterestType, CompoundingPeriod, MinBalance, Summary0) ->
    case find_savings_product(Name, Currency) of
        {ok, Product} ->
            {ok, element(2, Product), inc(savings_products_existing, Summary0)};
        not_found ->
            case cb_savings_products:create_product(Name, Description, Currency, InterestRate, InterestType, CompoundingPeriod, MinBalance) of
                {ok, Product} ->
                    {ok, element(2, Product), inc(savings_products_created, Summary0)};
                {error, Reason} ->
                    {error, Reason}
            end
    end.

ensure_loan_product(Name, Description, Currency, MinAmount, MaxAmount, MinTerm, MaxTerm, InterestRate, InterestType, Summary0) ->
    case find_loan_product(Name, Currency) of
        {ok, Product} ->
            {ok, Product#loan_product.product_id, inc(loan_products_existing, Summary0)};
        not_found ->
            case cb_loan_products:create_product(Name, Description, Currency, MinAmount, MaxAmount, MinTerm, MaxTerm, InterestRate, InterestType) of
                {ok, ProductId} ->
                    {ok, ProductId, inc(loan_products_created, Summary0)};
                {error, Reason} ->
                    {error, Reason}
            end
    end.

ensure_payment_txn(IdempotencyKey, Fun, Summary0) ->
    case find_txn_by_key(IdempotencyKey) of
        {ok, _Txn} ->
            {ok, inc(transactions_existing, Summary0)};
        not_found ->
            case Fun() of
                {ok, _Txn} ->
                    {ok, inc(transactions_created, Summary0)};
                {error, Reason} ->
                    {error, Reason}
            end
    end.

ensure_hold(AccountId, Amount, Reason, Summary0) ->
    case cb_account_holds:list_holds(AccountId) of
        {ok, Holds} ->
            case lists:any(fun(H) ->
                H#account_hold.status =:= active andalso
                H#account_hold.amount =:= Amount andalso
                H#account_hold.reason =:= Reason
            end, Holds) of
                true ->
                    {ok, inc(holds_existing, Summary0)};
                false ->
                    case cb_account_holds:place_hold(AccountId, Amount, Reason, undefined) of
                        {ok, _Hold} ->
                            {ok, inc(holds_created, Summary0)};
                        {error, ReasonAtom} ->
                            {error, ReasonAtom}
                    end
            end;
        {error, ReasonAtom} ->
            {error, ReasonAtom}
    end.

ensure_loan_with_repayment(ProductId, PartyId, AccountId, Principal, Currency, TermMonths, InterestRate, RepaymentAmount, Summary0) ->
    case find_loan(ProductId, PartyId, AccountId, Principal, Currency, TermMonths) of
        {ok, Loan} ->
            ensure_loan_state_and_repayment(Loan#loan_account.loan_id, Loan, RepaymentAmount, inc(loans_existing, Summary0));
        not_found ->
            case cb_loan_accounts:create_loan(ProductId, PartyId, AccountId, Principal, Currency, TermMonths, InterestRate) of
                {ok, LoanId} ->
                    case cb_loan_accounts:get_loan(LoanId) of
                        {ok, Loan} ->
                            ensure_loan_state_and_repayment(LoanId, Loan, RepaymentAmount, inc(loans_created, Summary0));
                        {error, Reason} ->
                            {error, Reason}
                    end;
                {error, Reason} ->
                    {error, Reason}
            end
    end.

ensure_loan_state_and_repayment(LoanId, Loan, RepaymentAmount, Summary0) ->
    case ensure_loan_disbursed(LoanId, Loan) of
        {ok, _UpdatedLoan} ->
            ensure_loan_repayment(LoanId, RepaymentAmount, Summary0);
        {error, Reason} ->
            {error, Reason}
    end.

ensure_loan_disbursed(LoanId, Loan) ->
    case Loan#loan_account.status of
        pending ->
            case cb_loan_accounts:approve_loan(LoanId) of
                {ok, ApprovedLoan} ->
                    ensure_loan_disbursed(LoanId, ApprovedLoan);
                {error, Reason} ->
                    {error, Reason}
            end;
        approved ->
            case cb_loan_accounts:disburse_loan(LoanId) of
                {ok, DisbursedLoan} ->
                    {ok, DisbursedLoan};
                {error, Reason} ->
                    {error, Reason}
            end;
        disbursed ->
            {ok, Loan};
        repaid ->
            {ok, Loan};
        _Other ->
            {error, invalid_status}
    end.

ensure_loan_repayment(LoanId, RepaymentAmount, Summary0) ->
    case cb_loan_accounts:get_loan(LoanId) of
        {ok, Loan} when Loan#loan_account.outstanding_balance < Loan#loan_account.principal ->
            {ok, inc(loan_repayments_existing, Summary0)};
        {ok, _Loan} ->
            case cb_loan_accounts:make_repayment(LoanId, RepaymentAmount) of
                {ok, _UpdatedLoan, _Outstanding} ->
                    {ok, inc(loan_repayments_created, Summary0)};
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

find_party_by_email(Email) ->
    Fun = fun() ->
        case mnesia:index_read(party, Email, email) of
            [Party | _] -> {ok, Party};
            [] -> not_found
        end
    end,
    case mnesia:transaction(Fun) of
        {atomic, Result} -> Result;
        {aborted, _} -> {error, database_error}
    end.

find_party_id_by_email(Email) ->
    case find_party_by_email(Email) of
        {ok, Party} ->
            {ok, Party#party.party_id};
        not_found ->
            {error, party_not_found};
        {error, _} = Error ->
            Error
    end.

find_account(PartyId, Name, Currency) ->
    Fun = fun() ->
        Accounts = mnesia:index_read(account, PartyId, party_id),
        case lists:filter(fun(A) ->
            A#account.name =:= Name andalso A#account.currency =:= Currency
        end, Accounts) of
            [Account | _] -> {ok, Account};
            [] -> not_found
        end
    end,
    case mnesia:transaction(Fun) of
        {atomic, Result} -> Result;
        {aborted, _} -> {error, database_error}
    end.

find_savings_product(Name, Currency) ->
    Fun = fun() ->
        Pattern = {savings_product, '_', Name, '_', Currency, '_', '_', '_', '_', '_', '_', '_'},
        case mnesia:match_object(savings_product, Pattern, read) of
            [Product | _] -> {ok, Product};
            [] -> not_found
        end
    end,
    case mnesia:transaction(Fun) of
        {atomic, Result} -> Result;
        {aborted, _} -> {error, database_error}
    end.

find_loan_product(Name, Currency) ->
    Fun = fun() ->
        Pattern = #loan_product{
            product_id = '_',
            name = Name,
            description = '_',
            currency = Currency,
            min_amount = '_',
            max_amount = '_',
            min_term_months = '_',
            max_term_months = '_',
            interest_rate = '_',
            interest_type = '_',
            status = '_',
            created_at = '_',
            updated_at = '_'
        },
        case mnesia:match_object(loan_products, Pattern, read) of
            [Product | _] -> {ok, Product};
            [] -> not_found
        end
    end,
    case mnesia:transaction(Fun) of
        {atomic, Result} -> Result;
        {aborted, _} -> {error, database_error}
    end.

find_txn_by_key(IdempotencyKey) ->
    Fun = fun() ->
        case mnesia:index_read(transaction, IdempotencyKey, idempotency_key) of
            [Txn | _] -> {ok, Txn};
            [] -> not_found
        end
    end,
    case mnesia:transaction(Fun) of
        {atomic, Result} -> Result;
        {aborted, _} -> {error, database_error}
    end.

find_loan(ProductId, PartyId, AccountId, Principal, Currency, TermMonths) ->
    Loans = cb_loan_accounts:list_all_loans(),
    case lists:filter(fun(L) ->
        L#loan_account.product_id =:= ProductId andalso
        L#loan_account.party_id =:= PartyId andalso
        L#loan_account.account_id =:= AccountId andalso
        L#loan_account.principal =:= Principal andalso
        L#loan_account.currency =:= Currency andalso
        L#loan_account.term_months =:= TermMonths
    end, Loans) of
        [Loan | _] ->
            {ok, Loan};
        [] ->
            not_found
    end.
