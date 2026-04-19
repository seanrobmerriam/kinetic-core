-module(prop_account_holds).

-include_lib("proper/include/proper.hrl").
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    prop_available_balance_never_exceeds_ledger_balance/0,
    prop_released_holds_restore_available_balance/0
]).

%% Property: available balance is always <= ledger balance
-spec prop_available_balance_never_exceeds_ledger_balance() -> term().
prop_available_balance_never_exceeds_ledger_balance() ->
    ?SETUP(fun setup_mnesia/0,
        ?FORALL({Deposit, HoldAmount}, hold_case(),
            begin
                ok = reset_tables(),
                {AccountId, Currency} = create_account('USD'),
                ok = seed_balance(AccountId, Currency, Deposit),
                {ok, _Hold} = cb_account_holds:place_hold(AccountId, HoldAmount, <<"prop test">>, undefined),
                {ok, Account} = cb_accounts:get_account(AccountId),
                {ok, Avail} = cb_account_holds:get_available_balance(AccountId),
                LedgerBalance = Account#account.balance,
                Avail =< LedgerBalance
            end
        )
    ).

%% Property: releasing a hold restores the available balance
-spec prop_released_holds_restore_available_balance() -> term().
prop_released_holds_restore_available_balance() ->
    ?SETUP(fun setup_mnesia/0,
        ?FORALL({Deposit, HoldAmount}, hold_case(),
            begin
                ok = reset_tables(),
                {AccountId, Currency} = create_account('USD'),
                ok = seed_balance(AccountId, Currency, Deposit),
                {ok, AvailBefore} = cb_account_holds:get_available_balance(AccountId),
                {ok, Hold} = cb_account_holds:place_hold(AccountId, HoldAmount, <<"prop test">>, undefined),
                {ok, _} = cb_account_holds:release_hold(Hold#account_hold.hold_id),
                {ok, AvailAfter} = cb_account_holds:get_available_balance(AccountId),
                AvailBefore =:= AvailAfter
            end
        )
    ).

%% ─── Generators ─────────────────────────────────────────────────────────────

hold_case() ->
    ?LET({HoldAmount, Extra},
         {range(1, 100000), range(0, 100000)},
         {HoldAmount + Extra, HoldAmount}).

%% ─── Helpers ────────────────────────────────────────────────────────────────

setup_mnesia() ->
    case mnesia:start() of
        ok -> ok;
        {error, {already_started, _}} -> ok
    end,
    cb_schema:create_tables(),
    fun() ->
        mnesia:stop(),
        mnesia:delete_schema([node()]),
        ok
    end.

reset_tables() ->
    Tables = [party, account, account_hold, transaction, ledger_entry],
    lists:foreach(
        fun(T) -> {atomic, ok} = mnesia:clear_table(T) end,
        Tables
    ),
    ok.

create_account(Currency) ->
    {ok, Party}   = cb_party:create_party(<<"PropEr Holds">>, unique_email()),
    {ok, Account} = cb_accounts:create_account(Party#party.party_id, <<"Checking">>, Currency),
    {Account#account.account_id, Currency}.

seed_balance(_AccountId, _Currency, 0) ->
    ok;
seed_balance(AccountId, Currency, Amount) ->
    {ok, _} = cb_payments:deposit(unique_id(<<"seed-">>), AccountId, Amount, Currency, <<"Seed">>),
    ok.

unique_id(Prefix) ->
    <<Prefix/binary, (uuid:uuid_to_string(uuid:get_v4(), binary_standard))/binary>>.

unique_email() ->
    <<(unique_id(<<"props-">>))/binary, "@example.com">>.
