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

    %% Bulk demo dataset: ensures the dashboard has a meaningful volume of
    %% records to exercise pagination, search, and reporting flows. All
    %% generators are deterministic and idempotent so re-running the importer
    %% does not produce duplicates.
    BulkPartyCount = 3000,
    BulkLoanCount = 4485,
    case bulk_ensure_parties(BulkPartyCount, Summary15) of
        {ok, BulkParties, Summary16} ->
            case bulk_ensure_deposits(BulkParties, Summary16) of
                {ok, Summary17} ->
                    case bulk_ensure_loans(LoanProductId, BulkParties, BulkLoanCount, Summary17) of
                        {ok, Summary18} ->
                            {ok, Summary18};
                        {error, _} = Err -> Err
                    end;
                {error, _} = Err -> Err
            end;
        {error, _} = Err -> Err
    end.

%% --- Bulk demo dataset helpers -------------------------------------------

bulk_ensure_parties(Count, Summary0) ->
    Names = load_names(),
    bulk_ensure_parties(1, Count, Names, [], Summary0).

bulk_ensure_parties(N, Count, _Names, Acc, Summary) when N > Count ->
    {ok, lists:reverse(Acc), Summary};
bulk_ensure_parties(N, Count, Names, Acc, Summary0) ->
    NLen = length(Names),
    FirstName = lists:nth(((N - 1) rem NLen) + 1, Names),
    LastIdx = ((N * 97) rem NLen) + 1,
    LastName = lists:nth(LastIdx, Names),
    FullName = <<FirstName/binary, " ", LastName/binary>>,
    Idx = integer_to_binary(N),
    Email = <<"mock-", Idx/binary, "@ironledger.dev">>,
    AccountName = <<"Main Checking">>,
    case ensure_party_account(FullName, Email, AccountName, 'USD', Summary0) of
        {ok, AccountId, Summary1} ->
            case find_party_id_by_email(Email) of
                {ok, PartyId} ->
                    Age = 18 + ((N * 7) rem 83),
                    SsnInt = 100000000 + ((N * 97331) rem 900000000),
                    Ssn = integer_to_binary(SsnInt),
                    Address = mock_address(N),
                    _ = cb_party:update_age(PartyId, Age),
                    _ = cb_party:update_ssn(PartyId, Ssn),
                    _ = cb_party:update_address(PartyId, Address),
                    bulk_ensure_parties(N + 1, Count, Names, [{PartyId, AccountId} | Acc], Summary1);
                {error, _} = Err ->
                    Err
            end;
        {error, _} = Err ->
            Err
    end.

load_names() ->
    PrivDir = code:priv_dir(cb_integration),
    FilePath = filename:join(PrivDir, "btn_givennames.txt"),
    {ok, Bin} = file:read_file(FilePath),
    Lines = binary:split(Bin, <<"\n">>, [global]),
    lists:filtermap(
        fun(Line) ->
            Trimmed = string:trim(Line),
            case Trimmed of
                <<"#", _/binary>> -> false;
                <<>> -> false;
                _ ->
                    Parts = binary:split(Trimmed, <<"\t">>),
                    case Parts of
                        [Name | _] when byte_size(Name) > 0 ->
                            case capitalize(Name) of
                                skip -> false;
                                Capitalized -> {true, Capitalized}
                            end;
                        _ -> false
                    end
            end
        end,
        Lines
    ).

capitalize(<<>>) ->
    skip;
capitalize(Bin) ->
    case unicode:characters_to_list(Bin, utf8) of
        {error, _, _} -> skip;
        {incomplete, _, _} -> skip;
        Chars when is_list(Chars) ->
            case string:titlecase(Chars) of
                [] -> skip;
                Title ->
                    case unicode:characters_to_binary(Title, utf8, utf8) of
                        {error, _, _} -> skip;
                        {incomplete, _, _} -> skip;
                        Out when is_binary(Out) -> Out
                    end
            end
    end.

mock_address(N) ->
    Streets = [<<"Main St">>, <<"Oak Ave">>, <<"Elm St">>, <<"Park Blvd">>,
               <<"Maple Dr">>, <<"Cedar Ln">>, <<"Pine Rd">>, <<"River Rd">>,
               <<"Lake Dr">>, <<"Hill St">>, <<"Valley Way">>, <<"Forest Ave">>,
               <<"Sunset Blvd">>, <<"Spring St">>, <<"Church Rd">>, <<"Mill Rd">>,
               <<"Highland Ave">>, <<"Orchard Ln">>, <<"Washington St">>, <<"Lincoln Ave">>],
    Cities = [<<"Springfield">>, <<"Franklin">>, <<"Clinton">>, <<"Georgetown">>,
              <<"Madison">>, <<"Salem">>, <<"Fairview">>, <<"Riverside">>,
              <<"Greenville">>, <<"Centerville">>, <<"Lakewood">>, <<"Hillside">>,
              <<"Oakdale">>, <<"Maplewood">>, <<"Chester">>, <<"Burlington">>,
              <<"Ashland">>, <<"Millbrook">>, <<"Ridgeway">>, <<"Westfield">>],
    States = [<<"CA">>, <<"TX">>, <<"NY">>, <<"FL">>, <<"IL">>,
              <<"PA">>, <<"OH">>, <<"GA">>, <<"NC">>, <<"MI">>],
    Len = 20,
    StateLen = 10,
    StreetNum = integer_to_binary(100 + ((N * 13) rem 9900)),
    Street = lists:nth((N rem Len) + 1, Streets),
    City = lists:nth(((N * 3) rem Len) + 1, Cities),
    State = lists:nth((N rem StateLen) + 1, States),
    Zip = integer_to_binary(10000 + ((N * 31) rem 90000)),
    #{
        line1 => <<StreetNum/binary, " ", Street/binary>>,
        city => City,
        state => State,
        postal_code => Zip,
        country => <<"US">>
    }.

bulk_ensure_deposits(Parties, Summary0) ->
    bulk_ensure_deposits(Parties, 1, Summary0).

bulk_ensure_deposits([], _N, Summary) ->
    {ok, Summary};
bulk_ensure_deposits([{_PartyId, AccountId} | Rest], N, Summary0) ->
    Idx = pad3(N),
    Key = <<"mock-bulk-deposit-", Idx/binary>>,
    Amount = 100000 + (N * 1000),
    Description = <<"Bulk demo deposit ", Idx/binary>>,
    case ensure_payment_txn(
        Key,
        fun() -> cb_payments:deposit(Key, AccountId, Amount, 'USD', Description) end,
        Summary0
    ) of
        {ok, Summary1} ->
            bulk_ensure_deposits(Rest, N + 1, Summary1);
        {error, _} = Err ->
            Err
    end.

-dialyzer({nowarn_function, bulk_ensure_loans/4}).
bulk_ensure_loans(_ProductId, _Parties, 0, Summary) ->
    {ok, Summary};
bulk_ensure_loans(_ProductId, [], _Remaining, Summary) ->
    {ok, Summary};
bulk_ensure_loans(ProductId, Parties, Remaining, Summary0) ->
    bulk_ensure_loans_loop(ProductId, Parties, Parties, 1, Remaining, Summary0).

bulk_ensure_loans_loop(_ProductId, _AllParties, _Cursor, _N, 0, Summary) ->
    {ok, Summary};
bulk_ensure_loans_loop(ProductId, AllParties, [], N, Remaining, Summary) ->
    bulk_ensure_loans_loop(ProductId, AllParties, AllParties, N, Remaining, Summary);
bulk_ensure_loans_loop(ProductId, AllParties, [{PartyId, AccountId} | Rest], N, Remaining, Summary0) ->
    %% Vary the principal per loan so that each {product, party, account,
    %% principal, currency, term} tuple is unique and the find_loan
    %% idempotency guard correctly distinguishes seeded loans on re-runs.
    %%
    %% The Personal Flex Loan product is created with min_amount=50000 and
    %% max_amount=2000000 (see ensure_loan_product/9 call above). Bulk
    %% imports request thousands of loans, so the principal must wrap
    %% within that range to avoid amount_out_of_product_range. Stepping by
    %% 1000 minor units gives 1951 distinct slots in [50000, 2000000];
    %% consecutive loans for the same party land 3000 iterations apart,
    %% which maps to a different slot, preserving the per-party
    %% idempotency tuple.
    MinPrincipal = 50000,
    MaxPrincipal = 2000000,
    Step = 1000,
    RangeSlots = (MaxPrincipal - MinPrincipal) div Step + 1,
    Principal = MinPrincipal + ((N - 1) rem RangeSlots) * Step,
    TermMonths = 12,
    InterestRate = 850,
    case ensure_loan_pending(ProductId, PartyId, AccountId, Principal, 'USD', TermMonths, InterestRate, Summary0) of
        {ok, Summary1} ->
            bulk_ensure_loans_loop(ProductId, AllParties, Rest, N + 1, Remaining - 1, Summary1);
        {error, _} = Err ->
            Err
    end.

ensure_loan_pending(ProductId, PartyId, AccountId, Principal, Currency, TermMonths, InterestRate, Summary0) ->
    case find_loan(ProductId, PartyId, AccountId, Principal, Currency, TermMonths) of
        {ok, _Loan} ->
            {ok, inc(loans_existing, Summary0)};
        not_found ->
            case cb_loan_accounts:create_loan(ProductId, PartyId, AccountId, Principal, Currency, TermMonths, InterestRate) of
                {ok, _LoanId} ->
                    {ok, inc(loans_created, Summary0)};
                {error, Reason} ->
                    {error, Reason}
            end
    end.

pad3(N) when is_integer(N), N >= 0 ->
    Bin = integer_to_binary(N),
    case byte_size(Bin) of
        1 -> <<"00", Bin/binary>>;
        2 -> <<"0", Bin/binary>>;
        _ -> Bin
    end.

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

-dialyzer({nowarn_function, find_loan_product/2}).
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
