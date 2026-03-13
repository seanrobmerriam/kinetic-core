-module(cb_accounts).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    create_account/3,
    get_account/1,
    list_accounts_for_party/3,
    freeze_account/1,
    unfreeze_account/1,
    close_account/1,
    get_balance/1
]).

%% Supported currencies
-define(VALID_CURRENCIES, ['USD', 'EUR', 'GBP', 'JPY', 'CHF']).

%% @doc Create a new account for a party.
-spec create_account(uuid(), binary(), currency()) -> {ok, #account{}} | {error, atom()}.
create_account(PartyId, Name, Currency) when is_binary(Name) ->
    case lists:member(Currency, ?VALID_CURRENCIES) of
        true ->
            F = fun() ->
                %% Verify party exists
                case mnesia:read(party, PartyId) of
                    [] ->
                        {error, party_not_found};
                    [Party] ->
                        case Party#party.status of
                            closed ->
                                {error, party_closed};
                            _ ->
                                Now = erlang:system_time(millisecond),
                                AccountId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
                                Account = #account{
                                    account_id = AccountId,
                                    party_id = PartyId,
                                    name = Name,
                                    currency = Currency,
                                    balance = 0,
                                    status = active,
                                    created_at = Now,
                                    updated_at = Now
                                },
                                mnesia:write(Account),
                                {ok, Account}
                        end
                end
            end,
            case mnesia:transaction(F) of
                {atomic, Result} -> Result;
                {aborted, _Reason} -> {error, database_error}
            end;
        false ->
            {error, unsupported_currency}
    end.

%% @doc Get an account by ID.
-spec get_account(uuid()) -> {ok, #account{}} | {error, atom()}.
get_account(AccountId) ->
    F = fun() ->
        case mnesia:read(account, AccountId) of
            [Account] -> {ok, Account};
            [] -> {error, account_not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

%% @doc List accounts for a party with pagination.
-spec list_accounts_for_party(uuid(), pos_integer(), pos_integer()) ->
    {ok, #{items => [#account{}], total => non_neg_integer(), page => pos_integer(), page_size => pos_integer()}} |
    {error, atom()}.
list_accounts_for_party(PartyId, Page, PageSize) when Page >= 1, PageSize >= 1, PageSize =< 100 ->
    F = fun() ->
        %% Verify party exists
        case mnesia:read(party, PartyId) of
            [] ->
                {error, party_not_found};
            _ ->
                Accounts = mnesia:index_read(account, PartyId, party_id),
                Sorted = lists:sort(
                    fun(A, B) -> A#account.created_at >= B#account.created_at end,
                    Accounts
                ),
                Total = length(Sorted),
                Offset = (Page - 1) * PageSize,
                Items = lists:sublist(Sorted, Offset + 1, PageSize),
                #{items => Items, total => Total, page => Page, page_size => PageSize}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, {error, _} = Error} -> Error;
        {atomic, Result} -> {ok, Result};
        {aborted, _Reason} -> {error, database_error}
    end;
list_accounts_for_party(_, _, _) ->
    {error, invalid_pagination}.

%% @doc Freeze an account.
-spec freeze_account(uuid()) -> {ok, #account{}} | {error, atom()}.
freeze_account(AccountId) ->
    F = fun() ->
        case mnesia:read(account, AccountId, write) of
            [Account] ->
                case Account#account.status of
                    active ->
                        Now = erlang:system_time(millisecond),
                        Updated = Account#account{status = frozen, updated_at = Now},
                        mnesia:write(Updated),
                        {ok, Updated};
                    frozen ->
                        {error, account_already_frozen};
                    closed ->
                        {error, account_closed}
                end;
            [] ->
                {error, account_not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

%% @doc Unfreeze an account.
-spec unfreeze_account(uuid()) -> {ok, #account{}} | {error, atom()}.
unfreeze_account(AccountId) ->
    F = fun() ->
        case mnesia:read(account, AccountId, write) of
            [Account] ->
                case Account#account.status of
                    frozen ->
                        Now = erlang:system_time(millisecond),
                        Updated = Account#account{status = active, updated_at = Now},
                        mnesia:write(Updated),
                        {ok, Updated};
                    active ->
                        {error, account_not_frozen};
                    closed ->
                        {error, account_closed}
                end;
            [] ->
                {error, account_not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

%% @doc Close an account. Balance must be zero.
-spec close_account(uuid()) -> {ok, #account{}} | {error, atom()}.
close_account(AccountId) ->
    F = fun() ->
        case mnesia:read(account, AccountId, write) of
            [Account] ->
                case Account#account.balance of
                    0 ->
                        Now = erlang:system_time(millisecond),
                        Updated = Account#account{status = closed, updated_at = Now},
                        mnesia:write(Updated),
                        {ok, Updated};
                    _ ->
                        {error, account_has_balance}
                end;
            [] ->
                {error, account_not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

%% @doc Get account balance.
-spec get_balance(uuid()) -> {ok, #{account_id => uuid(), currency => currency(), balance => amount(), balance_formatted => binary()}} | {error, atom()}.
get_balance(AccountId) ->
    F = fun() ->
        case mnesia:read(account, AccountId) of
            [Account] ->
                Formatted = format_balance(Account#account.balance, Account#account.currency),
                {ok, #{
                    account_id => AccountId,
                    currency => Account#account.currency,
                    balance => Account#account.balance,
                    balance_formatted => Formatted
                }};
            [] ->
                {error, account_not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

%% @private Format balance for display.
-spec format_balance(amount(), currency()) -> binary().
format_balance(Balance, 'JPY') ->
    iolist_to_binary([<<"¥">>, integer_to_binary(Balance)]);
format_balance(Balance, 'USD') ->
    iolist_to_binary([<<"$">>, format_decimal(Balance)]);
format_balance(Balance, 'EUR') ->
    iolist_to_binary([<<"€">>, format_decimal(Balance)]);
format_balance(Balance, 'GBP') ->
    iolist_to_binary([<<"£">>, format_decimal(Balance)]);
format_balance(Balance, 'CHF') ->
    iolist_to_binary([<<"CHF ">>, format_decimal(Balance)]).

-spec format_decimal(amount()) -> binary().
format_decimal(Amount) ->
    Dollars = Amount div 100,
    Cents = Amount rem 100,
    iolist_to_binary([
        integer_to_binary(Dollars),
        <<".">>,
        string:pad(integer_to_binary(Cents), 2, leading, "0")
    ]).
