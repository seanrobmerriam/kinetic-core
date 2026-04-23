%% @doc Development mock data importer.
%%
%% Seeds the database from names.csv (apps/cb_integration/priv/names.csv).
%% Every identity receives at least one product (checking account).
%% ~25% also receive a savings account; ~33% also receive a pending loan.
%% The import is idempotent — safe to run repeatedly.

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
    {ok, _GrowthSavingsProductId, Summary1} = ensure_savings_product(
        <<"Growth Saver">>,
        <<"Demo high-yield savings product">>,
        'USD',
        425,
        compound,
        monthly,
        10000,
        Summary0
    ),
    {ok, _StarterSavingsProductId, Summary2} = ensure_savings_product(
        <<"Starter Saver">>,
        <<"Demo starter savings product">>,
        'USD',
        150,
        simple,
        monthly,
        0,
        Summary1
    ),
    {ok, LoanProductId, Summary3} = ensure_loan_product(
        <<"Personal Flex Loan">>,
        <<"Demo unsecured personal loan">>,
        'USD',
        50000,
        2000000,
        6,
        60,
        850,
        declining,
        Summary2
    ),
    bulk_ensure_csv_parties(LoanProductId, Summary3).

%% --- CSV-based bulk import ------------------------------------------------

bulk_ensure_csv_parties(LoanProductId, Summary0) ->
    Identities = load_csv_identities(),
    bulk_ensure_csv_parties(Identities, 1, LoanProductId, Summary0).

bulk_ensure_csv_parties([], _N, _LoanProductId, Summary) ->
    {ok, Summary};
bulk_ensure_csv_parties([Identity | Rest], N, LoanProductId, Summary0) ->
    #{full_name := FullName, base_email := BaseEmail, age := Age} = Identity,
    %% Make email unique by appending the row index (the CSV has ~1600 unique
    %% base emails across 4002 rows).
    [LocalPart, Domain] = binary:split(BaseEmail, <<"@">>),
    Email = <<LocalPart/binary, "-", (integer_to_binary(N))/binary, "@", Domain/binary>>,
    case ensure_party_account(FullName, Email, <<"Main Checking">>, 'USD', Summary0) of
        {ok, CheckingId, Summary1} ->
            {ok, PartyId} = find_party_id_by_email(Email),
            SsnInt = 100000000 + ((N * 97331) rem 900000000),
            _ = cb_party:update_age(PartyId, Age),
            _ = cb_party:update_ssn(PartyId, integer_to_binary(SsnInt)),
            _ = cb_party:update_address(PartyId, mock_address(N)),
            DepKey = <<"csv-deposit-", (integer_to_binary(N))/binary>>,
            DepAmount = 100000 + (N * 1000),
            {ok, Summary2} = ensure_payment_txn(
                DepKey,
                fun() -> cb_payments:deposit(DepKey, CheckingId, DepAmount, 'USD', <<"Initial deposit">>) end,
                Summary1
            ),
            %% Every 4th person also gets a savings account.
            Summary3 = case N rem 4 of
                0 ->
                    case ensure_account(PartyId, <<"Savings Account">>, 'USD', Summary2) of
                        {ok, SavId, S3} ->
                            SavKey = <<"csv-sav-deposit-", (integer_to_binary(N))/binary>>,
                            SavAmount = 50000 + (N * 500),
                            case ensure_payment_txn(
                                SavKey,
                                fun() -> cb_payments:deposit(SavKey, SavId, SavAmount, 'USD', <<"Savings deposit">>) end,
                                S3
                            ) of
                                {ok, S4} -> S4;
                                {error, _} -> S3
                            end;
                        {error, _} -> Summary2
                    end;
                _ -> Summary2
            end,
            %% Every 3rd person also gets a pending loan.
            Summary4 = case N rem 3 of
                0 ->
                    MinP = 50000,
                    MaxP = 2000000,
                    Step = 1000,
                    Slots = (MaxP - MinP) div Step + 1,
                    Principal = MinP + ((N - 1) rem Slots) * Step,
                    case ensure_loan_pending(LoanProductId, PartyId, CheckingId, Principal, 'USD', 12, 850, Summary3) of
                        {ok, S5} -> S5;
                        {error, _} -> Summary3
                    end;
                _ -> Summary3
            end,
            bulk_ensure_csv_parties(Rest, N + 1, LoanProductId, Summary4);
        {error, Reason} ->
            {error, Reason}
    end.

%% --- CSV identity loader --------------------------------------------------

load_csv_identities() ->
    PrivDir = code:priv_dir(cb_integration),
    FilePath = filename:join(PrivDir, "names.csv"),
    {ok, Bin} = file:read_file(FilePath),
    Lines = binary:split(Bin, <<"\n">>, [global]),
    %% Skip header line.
    case Lines of
        [_Header | DataLines] ->
            lists:filtermap(fun parse_csv_identity/1, DataLines);
        _ ->
            []
    end.

parse_csv_identity(<<>>) ->
    false;
parse_csv_identity(Line) ->
    Fields = split_csv_line(Line),
    case Fields of
        [FirstName, LastName, _Gender, AgeStr, Email, _Phone, _Education, _Occupation, _Salary, _MaritalStatus] ->
            case binary:match(Email, <<"@">>) of
                nomatch ->
                    %% Skip header rows or rows with non-email in the email field.
                    false;
                _ ->
                    Age = try binary_to_integer(AgeStr) catch _:_ -> 30 end,
                    FullName = <<FirstName/binary, " ", LastName/binary>>,
                    {true, #{full_name => FullName, base_email => Email, age => Age}}
            end;
        _ ->
            false
    end.

%% Split a CSV line of the form: "f1","f2",...,"fN"
%% Splits on the three-char token `","` so inner quotes are preserved.
split_csv_line(Line) ->
    Parts = binary:split(Line, <<"\",\"">>, [global]),
    case Parts of
        [First | [_ | _] = Rest] ->
            FirstClean = case First of
                <<"\"", F/binary>> -> F;
                F -> F
            end,
            AllButLast = lists:droplast(Rest),
            Last = lists:last(Rest),
            LastClean = strip_trailing_quote_cr(Last),
            [FirstClean | AllButLast] ++ [LastClean];
        _ ->
            Parts
    end.

strip_trailing_quote_cr(<<>>) ->
    <<>>;
strip_trailing_quote_cr(Bin) ->
    S1 = case binary:last(Bin) of
        $\r -> binary:part(Bin, 0, byte_size(Bin) - 1);
        _   -> Bin
    end,
    case byte_size(S1) of
        0 -> <<>>;
        _ ->
            case binary:last(S1) of
                $\" -> binary:part(S1, 0, byte_size(S1) - 1);
                _   -> S1
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
