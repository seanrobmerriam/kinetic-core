%% @doc Beneficiary (payee) management for payment orders.
%%
%% Manages registered beneficiaries that can be referenced when creating
%% payment orders, avoiding repeated entry of payee details.
%%
%% Duplicate detection is based on account_number + bank_code + country.
-module(cb_beneficiary).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    create_beneficiary/6,
    get_beneficiary/1,
    list_beneficiaries/1,
    update_beneficiary/2,
    delete_beneficiary/1,
    find_duplicate/3
]).

-define(TABLE, beneficiary).

%% @doc Create a new beneficiary for a party.
-spec create_beneficiary(uuid(), binary(), binary(), binary(), currency(), binary()) ->
    {ok, #beneficiary{}} | {error, duplicate_beneficiary | party_not_found | invalid_data}.
create_beneficiary(PartyId, Name, AccountNumber, BankCode, Currency, Country) ->
    case find_duplicate(AccountNumber, BankCode, Country) of
        {ok, _Existing} -> {error, duplicate_beneficiary};
        not_found ->
            case cb_party:get_party(PartyId) of
                {error, _} -> {error, party_not_found};
                {ok, _Party} ->
                    BeneficiaryId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
                    Now = erlang:system_time(millisecond),
                    Record = #beneficiary{
                        beneficiary_id  = BeneficiaryId,
                        party_id        = PartyId,
                        name            = Name,
                        account_number  = AccountNumber,
                        bank_code       = BankCode,
                        currency        = Currency,
                        country         = Country,
                        is_active       = true,
                        created_at      = Now,
                        updated_at      = Now
                    },
                    F = fun() -> mnesia:write(?TABLE, Record, write) end,
                    case mnesia:transaction(F) of
                        {atomic, ok} -> {ok, Record};
                        {aborted, Reason} -> {error, Reason}
                    end
            end
    end.

%% @doc Get a beneficiary by its ID.
-spec get_beneficiary(binary()) -> {ok, #beneficiary{}} | {error, not_found}.
get_beneficiary(BeneficiaryId) ->
    case mnesia:dirty_read(?TABLE, BeneficiaryId) of
        [] -> {error, not_found};
        [Beneficiary] -> {ok, Beneficiary}
    end.

%% @doc List all beneficiaries for a party (optionally filtered by party_id).
-spec list_beneficiaries(binary() | undefined) -> [#beneficiary{}].
list_beneficiaries(undefined) ->
    mnesia:dirty_match_object(?TABLE, #beneficiary{_ = '_'});
list_beneficiaries(PartyId) ->
    mnesia:dirty_index_read(?TABLE, PartyId, party_id).

%% @doc Update a beneficiary's details.
-spec update_beneficiary(binary(), map()) ->
    {ok, #beneficiary{}} | {error, not_found | invalid_data}.
update_beneficiary(BeneficiaryId, Updates) ->
    case mnesia:dirty_read(?TABLE, BeneficiaryId) of
        [] -> {error, not_found};
        [Beneficiary] ->
            Updated = Beneficiary#beneficiary{
                name           = maps:get(name, Updates, Beneficiary#beneficiary.name),
                account_number = maps:get(account_number, Updates, Beneficiary#beneficiary.account_number),
                bank_code      = maps:get(bank_code, Updates, Beneficiary#beneficiary.bank_code),
                currency       = maps:get(currency, Updates, Beneficiary#beneficiary.currency),
                country        = maps:get(country, Updates, Beneficiary#beneficiary.country),
                is_active      = maps:get(is_active, Updates, Beneficiary#beneficiary.is_active),
                updated_at     = erlang:system_time(millisecond)
            },
            F = fun() -> mnesia:write(?TABLE, Updated, write) end,
            case mnesia:transaction(F) of
                {atomic, ok} -> {ok, Updated};
                {aborted, Reason} -> {error, Reason}
            end
    end.

%% @doc Soft-delete a beneficiary (set is_active = false).
-spec delete_beneficiary(binary()) -> {ok, #beneficiary{}} | {error, not_found}.
delete_beneficiary(BeneficiaryId) ->
    case mnesia:dirty_read(?TABLE, BeneficiaryId) of
        [] -> {error, not_found};
        [Beneficiary] ->
            Updated = Beneficiary#beneficiary{
                is_active  = false,
                updated_at = erlang:system_time(millisecond)
            },
            F = fun() -> mnesia:write(?TABLE, Updated, write) end,
            case mnesia:transaction(F) of
                {atomic, ok} -> {ok, Updated};
                {aborted, Reason} -> {error, Reason}
            end
    end.

%% @doc Find a duplicate beneficiary by account_number + bank_code + country.
-spec find_duplicate(binary(), binary(), binary()) -> {ok, #beneficiary{}} | not_found.
find_duplicate(AccountNumber, BankCode, Country) ->
    MatchSpec = [{
        #beneficiary{account_number = AccountNumber, bank_code = BankCode, country = Country, _ = '_'},
        [],
        ['$_']
    }],
    case mnesia:dirty_select(?TABLE, MatchSpec) of
        [] -> not_found;
        [Found | _] -> {ok, Found}
    end.