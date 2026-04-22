%% @doc
%% <h2>Party Management Module</h2>
%%
%% This module provides the core business logic for managing "parties" (also known as
%% "customers" or "clients") in the IronLedger core banking system.
%%
%% <h3>What is a Party?</h3>
%%
%% A <b>party</b> represents a legal entity (individual or organization) that can own
%% accounts and conduct financial transactions in the banking system. In banking terminology:
%%
%% <ul>
%%   <li><b>KYC (Know Your Customer)</b>: The process of verifying a party's identity
%%       before opening accounts. A party record represents a customer who has completed
%%       or is undergoing KYC verification.</li>
%%   <li><b>Customer/Client</b>: The business term for a party that has a relationship
%%       with the bank.</li>
%%   <li><b>Account Holder</b>: The party who owns one or more accounts.</li>
%% </ul>
%%
%% <h3>Party Lifecycle</h3>
%%
%% A party can be in one of three states:
%%
%% <ul>
%%   <li><b>active</b>: The party is in good standing, can open accounts, and conduct
%%       transactions.</li>
%%   <li><b>suspended</b>: The party cannot open new accounts or conduct transactions.
%%       Typically used during fraud investigations, regulatory holds, or at the customer's
%%       request (e.g., fraud alert). Existing accounts remain but are frozen.</li>
%%   <li><b>closed</b>: The party has no active accounts and no longer has a relationship
%%       with the bank. All accounts must be closed before a party can be closed.</li>
%% </ul>
%%
%% <h3>Business Rules</h3>
%%
%% <ul>
%%   <li>Each party must have a unique email address (used as an identifier)</li>
%%   <li>A party can hold multiple accounts (checking, savings, loans, etc.)</li>
%%   <li>Before a party can be closed, all their accounts must be closed first</li>
%%   <li>Suspending a party does not automatically freeze their accounts - that is
%%       handled separately by the account management module</li>
%% </ul>
%%
%% <h3>Data Model</h3>
%%
%% The party record contains:
%% <ul>
%%   <li><b>party_id</b>: Unique UUID identifier for the party</li>
%%   <li><b>full_name</b>: Legal name of the party (individual or organization)</li>
%%   <li><b>email</b>: Contact email address (also serves as unique identifier)</li>
%%   <li><b>status</b>: Current lifecycle state (active, suspended, closed)</li>
%%   <li><b>created_at</b>: Timestamp when the party record was created</li>
%%   <li><b>updated_at</b>: Timestamp of the last modification</li>
%% </ul>
%%
%% @see cb_ledger.hrl for the party record definition
-module(cb_party).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    create_party/2,
    get_party/1,
    list_parties/2,
    list_parties_filtered/3,
    suspend_party/1,
    reactivate_party/1,
    close_party/1,
    update_kyc_status/3,
    update_onboarding_status/2,
    add_doc_ref/2,
    update_address/2,
    update_age/2,
    update_ssn/2,
    detect_duplicate_parties/0,
    merge_parties/3,
    set_risk_tier/2,
    get_risk_tier/1,
    retention_days_for_tier/1
]).

%% @doc
%% Creates a new party (customer/client) in the banking system.
%%
%% This function registers a new customer who can then open accounts and conduct
%% financial transactions. The party is created in the <b>active</b> state.
%%
%% <h3>Business Rules</h3>
%% <ul>
%%   <li>The email address must be unique across all parties</li>
%%   <li>Full name cannot be empty</li>
%%   <li>In production, this would trigger KYC workflow initiation</li>
%% </ul>
%%
%% @param FullName The legal name of the party (individual or organization)
%% @param Email The party's contact email address (also serves as unique identifier)
%%
%% @return {ok, #party{}} - The newly created party record
%% @return {error, email_already_exists} - A party with this email already exists
%% @return {error, database_error} - Transaction failed (e.g., Mnesia unavailable)
%%
%% @spec create_party(binary(), binary()) -> {ok, #party{}} | {error, atom()}
create_party(FullName, Email) when is_binary(FullName), is_binary(Email) ->
    F = fun() ->
        %% Check for duplicate email
        case mnesia:index_read(party, Email, email) of
            [] ->
                Now = erlang:system_time(millisecond),
                PartyId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
                Party = #party{
                    party_id = PartyId,
                    full_name = FullName,
                    email = Email,
                    status = active,
                    kyc_status = not_started,
                    onboarding_status = incomplete,
                    review_notes = undefined,
                    doc_refs = [],
                    risk_tier = low,
                    address = undefined,
                    age = undefined,
                    ssn = undefined,
                    version = 1,
                    merged_into_party_id = undefined,
                    created_at = Now,
                    updated_at = Now
                },
                mnesia:write(Party),
                write_party_audit(PartyId, create, 1, #{email => Email}),
                {ok, Party};
            [_Existing] ->
                {error, email_already_exists}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

%% @doc
%% Retrieves a party by their unique identifier.
%%
%% Used to look up a party's details for account operations, transaction history,
%% or customer service inquiries.
%%
%% @param PartyId The UUID of the party to retrieve
%%
%% @return {ok, #party{}} - The party record with the given ID
%% @return {error, party_not_found} - No party exists with the given ID
%% @return {error, database_error} - Transaction failed
%%
%% @spec get_party(uuid()) -> {ok, #party{}} | {error, atom()}.
get_party(PartyId) ->
    F = fun() ->
        case mnesia:read(party, PartyId) of
            [Party] -> {ok, Party};
            [] -> {error, party_not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

%% @doc
%% Lists all parties with pagination support.
%%
%% Returns a paginated list of parties ordered by creation date (newest first).
%% This is typically used for administrative UIs and reporting.
%%
%% <h3>Pagination</h3>
%% <ul>
%%   <li>Page numbering starts at 1</li>
%%   <li>Maximum page size is 100 items</li>
%%   <li>Results include total count for calculating total pages</li>
%% </ul>
%%
%% @param Page The page number to retrieve (1-indexed)
%% @param PageSize Number of items per page (1-100)
%%
%% @return {ok, #{items => [#party{}], total => non_neg_integer(), page => pos_integer(), page_size => pos_integer()}}
%% @return {error, invalid_pagination} - Invalid page or page_size values
%% @return {error, database_error} - Transaction failed
%%
%% @spec list_parties(pos_integer(), pos_integer()) ->
%%     {ok, #{items => [#party{}], total => non_neg_integer(), page => pos_integer(), page_size => pos_integer()}} |
%%     {error, atom()}.
list_parties(Page, PageSize) when Page >= 1, PageSize >= 1, PageSize =< 100 ->
    F = fun() ->
        AllParties = mnesia:select(party, [{'_', [], ['$_']}]),
        Sorted = lists:sort(
            fun(A, B) -> A#party.created_at >= B#party.created_at end,
            AllParties
        ),
        Total = length(Sorted),
        Offset = (Page - 1) * PageSize,
        Items = lists:sublist(Sorted, Offset + 1, PageSize),
        #{items => Items, total => Total, page => Page, page_size => PageSize}
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> {ok, Result};
        {aborted, _Reason} -> {error, database_error}
    end;
list_parties(_, _) ->
    {error, invalid_pagination}.

%% @doc
%% Lists parties with optional filters and pagination.
%%
%% Supported filters map keys:
%% - status => active | suspended | closed
%% - email_contains => binary()
%%
%% @spec list_parties_filtered(pos_integer(), pos_integer(), map()) ->
%%     {ok, map()} | {error, atom()}.
list_parties_filtered(Page, PageSize, Filters)
        when Page >= 1, PageSize >= 1, PageSize =< 100, is_map(Filters) ->
    F = fun() ->
        AllParties = mnesia:select(party, [{'_', [], ['$_']}]),
        Matched = lists:filter(fun(P) -> matches_party_filters(P, Filters) end, AllParties),
        Sorted = lists:sort(
            fun(A, B) -> A#party.created_at >= B#party.created_at end,
            Matched
        ),
        Total = length(Sorted),
        Offset = (Page - 1) * PageSize,
        Items = lists:sublist(Sorted, Offset + 1, PageSize),
        #{items => Items, total => Total, page => Page, page_size => PageSize}
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> {ok, Result};
        {aborted, _Reason} -> {error, database_error}
    end;
list_parties_filtered(_, _, _) ->
    {error, invalid_pagination}.

%% @doc
%% Suspends a party, temporarily halting their banking relationship.
%%
%% Suspending a party prevents them from opening new accounts and conducting new
%% transactions. This is typically used in the following scenarios:
%%
%% <ul>
%%   <li><b>Fraud investigation</b>: When suspicious activity is detected</li>
%%   <li><b>Regulatory hold</b>: When required by law enforcement or regulator</li%%
%%   <li><b>Customer request</b>: When a customer reports fraud or loses credentials</li>
%%   <li><b>Credit issue</b>: When the party defaults on loan payments</li>
%% </ul>
%%
%% <h3>Important Notes</h3>
%% <ul>
%%   <li>Suspending a party does NOT automatically suspend their accounts</li>
%%   <li>Account suspension is handled separately by cb_accounts module</li>
%%   <li>The party's existing accounts remain accessible until explicitly frozen</li>
%% </ul>
%%
%% @param PartyId The UUID of the party to suspend
%%
%% @return {ok, #party{}} - The updated party with status = suspended
%% @return {error, party_not_found} - No party exists with the given ID
%% @return {error, party_already_suspended} - Party is already in suspended state
%% @return {error, party_closed} - Cannot suspend a closed party
%% @return {error, database_error} - Transaction failed
%%
%% @spec suspend_party(uuid()) -> {ok, #party{}} | {error, atom()}.
suspend_party(PartyId) ->
    F = fun() ->
        case mnesia:read(party, PartyId, write) of
            [Party] ->
                case Party#party.status of
                    active ->
                        Updated = bump_party_version(Party#party{status = suspended}),
                        mnesia:write(Updated),
                        write_party_audit(PartyId, suspend, Updated#party.version, #{}),
                        {ok, Updated};
                    suspended ->
                        {error, party_already_suspended};
                    closed ->
                        {error, party_closed}
                end;
            [] ->
                {error, party_not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

%% @doc
%% Reactivates a previously suspended party, restoring full banking privileges.
%%
%% This reverses the suspension, putting the party back into <b>active</b> state.
%% Typically called after:
%%
%% <ul>
%%   <li>Completion of fraud investigation with no findings</li>
%%   <li>Regulatory hold is released</li>
%%   <li>Customer verifies their identity after reporting compromise</li>
%%   <li>Loan default is resolved</li>
%% </ul>
%%
%% @param PartyId The UUID of the party to reactivate
%%
%% @return {ok, #party{}} - The updated party with status = active
%% @return {error, party_not_found} - No party exists with the given ID
%% @return {error, party_not_suspended} - Party is not in suspended state
%% @return {error, party_closed} - Cannot reactivate a closed party
%% @return {error, database_error} - Transaction failed
%%
%% @spec reactivate_party(uuid()) -> {ok, #party{}} | {error, atom()}.
reactivate_party(PartyId) ->
    F = fun() ->
        case mnesia:read(party, PartyId, write) of
            [Party] ->
                case Party#party.status of
                    suspended ->
                        Updated = bump_party_version(Party#party{status = active}),
                        mnesia:write(Updated),
                        write_party_audit(PartyId, reactivate, Updated#party.version, #{}),
                        {ok, Updated};
                    active ->
                        {error, party_not_suspended};
                    closed ->
                        {error, party_closed}
                end;
            [] ->
                {error, party_not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

%% @doc
%% Permanently closes a party's banking relationship.
%%
%% Closing a party marks the end of their relationship with the bank. This action
%% is irreversible - a closed party cannot be reopened, but a new party can be
%% created with the same details.
%%
%% <h3>Business Rules</h3>
%% <ul>
%%   <li>All accounts belonging to the party must be closed before the party can be closed</li>
%%   <li>Outstanding loans must be fully repaid</li>
%%   <li>All pending transactions must be completed or cancelled</li>
%%   <li>Final account balances must be zeroed (funds withdrawn or transferred)</li>
%% </ul>
%%
%% <h3>Use Cases</h3>
%% <ul>
%%   <li>Customer requests account closure</li>
%%   <li>Customer death (managed by authorized representative)</li>
%%   <li>Business closure</li>
%%   <li>Regulatory requirement (e.g., sanctions)</li>
%% </ul>
%%
%% @param PartyId The UUID of the party to close
%%
%% @return {ok, #party{}} - The updated party with status = closed
%% @return {error, party_not_found} - No party exists with the given ID
%% @return {error, party_closed} - Party is already closed
%% @return {error, party_has_active_accounts} - Party still has open accounts
%% @return {error, database_error} - Transaction failed
%%
%% @spec close_party(uuid()) -> {ok, #party{}} | {error, atom()}.
close_party(PartyId) ->
    F = fun() ->
        case mnesia:read(party, PartyId, write) of
            [Party] ->
                case Party#party.status of
                    closed ->
                        {error, party_closed};
                    _ ->
                        %% Check for active accounts
                        Accounts = mnesia:index_read(account, PartyId, party_id),
                        HasActive = lists:any(
                            fun(A) -> A#account.status =/= closed end,
                            Accounts
                        ),
                        case HasActive of
                            true ->
                                {error, party_has_active_accounts};
                            false ->
                                Updated = bump_party_version(Party#party{status = closed}),
                                mnesia:write(Updated),
                                write_party_audit(PartyId, close, Updated#party.version, #{}),
                                {ok, Updated}
                        end
                end;
            [] ->
                {error, party_not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

%% @doc
%% Updates the KYC verification status for a party.
%%
%% Valid statuses: not_started | pending | approved | rejected.
%% Notes is an optional binary explaining the review outcome.
%%
%% @spec update_kyc_status(uuid(), kyc_status(), binary() | undefined) -> {ok, #party{}} | {error, atom()}
update_kyc_status(PartyId, KycStatus, Notes)
        when KycStatus =:= not_started; KycStatus =:= pending;
             KycStatus =:= approved; KycStatus =:= rejected ->
    F = fun() ->
        case mnesia:read(party, PartyId) of
            [Party] ->
                Updated = bump_party_version(Party#party{
                    kyc_status = KycStatus,
                    review_notes = Notes
                }),
                mnesia:write(Updated),
                write_party_audit(PartyId, update_kyc_status, Updated#party.version, #{status => KycStatus}),
                {ok, Updated};
            [] ->
                {error, party_not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end;
update_kyc_status(_PartyId, _KycStatus, _Notes) ->
    {error, invalid_kyc_status}.

%% @doc
%% Updates the onboarding completion status for a party.
%%
%% Valid statuses: incomplete | complete.
%%
%% @spec update_onboarding_status(uuid(), onboarding_status()) -> {ok, #party{}} | {error, atom()}
update_onboarding_status(PartyId, OnboardingStatus)
        when OnboardingStatus =:= incomplete; OnboardingStatus =:= complete ->
    F = fun() ->
        case mnesia:read(party, PartyId) of
            [Party] ->
                Updated = bump_party_version(Party#party{
                    onboarding_status = OnboardingStatus
                }),
                mnesia:write(Updated),
                write_party_audit(PartyId, update_onboarding_status, Updated#party.version, #{status => OnboardingStatus}),
                {ok, Updated};
            [] ->
                {error, party_not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end;
update_onboarding_status(_PartyId, _Status) ->
    {error, invalid_onboarding_status}.

%% @doc
%% Adds a document reference to a party's KYC document list.
%%
%% DocRef is a binary identifier (e.g. S3 key, file hash) for an uploaded document.
%%
%% @spec add_doc_ref(uuid(), binary()) -> {ok, #party{}} | {error, atom()}
add_doc_ref(PartyId, DocRef) when is_binary(DocRef) ->
    F = fun() ->
        case mnesia:read(party, PartyId) of
            [Party] ->
                Existing = Party#party.doc_refs,
                Updated = bump_party_version(Party#party{
                    doc_refs = [DocRef | Existing],
                    updated_at = Party#party.updated_at
                }),
                mnesia:write(Updated),
                write_party_audit(PartyId, add_doc_ref, Updated#party.version, #{doc_ref => DocRef}),
                {ok, Updated};
            [] ->
                {error, party_not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

%% @doc
%% Updates the postal address associated with a party.
%%
%% @spec update_address(uuid(), party_address()) -> {ok, #party{}} | {error, atom()}.
update_address(PartyId, Address) when is_map(Address) ->
    case validate_address(Address) of
        ok ->
            F = fun() ->
                case mnesia:read(party, PartyId) of
                    [Party] ->
                        Updated = bump_party_version(Party#party{address = Address}),
                        mnesia:write(Updated),
                        write_party_audit(PartyId, update_address, Updated#party.version, #{}),
                        {ok, Updated};
                    [] ->
                        {error, party_not_found}
                end
            end,
            case mnesia:transaction(F) of
                {atomic, Result} -> Result;
                {aborted, _Reason} -> {error, database_error}
            end;
        {error, _} = Error ->
            Error
    end;
update_address(_, _) ->
    {error, invalid_address}.

%% @doc
%% Updates the age of a party.
%%
%% @spec update_age(uuid(), non_neg_integer()) -> {ok, #party{}} | {error, atom()}.
update_age(PartyId, Age) when is_integer(Age), Age >= 0 ->
    F = fun() ->
        case mnesia:read(party, PartyId) of
            [Party] ->
                Updated = bump_party_version(Party#party{age = Age}),
                mnesia:write(Updated),
                write_party_audit(PartyId, update_age, Updated#party.version, #{age => Age}),
                {ok, Updated};
            [] ->
                {error, party_not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end;
update_age(_, _) ->
    {error, invalid_age}.

%% @doc
%% Updates the SSN of a party.
%%
%% @spec update_ssn(uuid(), binary()) -> {ok, #party{}} | {error, atom()}.
update_ssn(PartyId, Ssn) when is_binary(Ssn) ->
    F = fun() ->
        case mnesia:read(party, PartyId) of
            [Party] ->
                Updated = bump_party_version(Party#party{ssn = Ssn}),
                mnesia:write(Updated),
                write_party_audit(PartyId, update_ssn, Updated#party.version, #{}),
                {ok, Updated};
            [] ->
                {error, party_not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end;
update_ssn(_, _) ->
    {error, invalid_ssn}.

%% @doc
%% Detects likely duplicate parties by normalized full name.
%%
%% Returns groups where more than one party has the same normalized name.
%%
%% @spec detect_duplicate_parties() -> {ok, [#{normalized_name => binary(), party_ids => [uuid()]}]} | {error, atom()}.
detect_duplicate_parties() ->
    F = fun() ->
        AllParties = mnesia:select(party, [{'_', [], ['$_']}]),
        Grouped = lists:foldl(
            fun(Party, Acc) ->
                NameKey = normalize_name(Party#party.full_name),
                Existing = maps:get(NameKey, Acc, []),
                maps:put(NameKey, [Party | Existing], Acc)
            end,
            #{},
            AllParties
        ),
        Duplicates = maps:fold(
            fun(NameKey, Parties, Out) ->
                case length(Parties) > 1 of
                    true ->
                        [#{
                            normalized_name => NameKey,
                            party_ids => [P#party.party_id || P <- Parties]
                        } | Out];
                    false ->
                        Out
                end
            end,
            [],
            Grouped
        ),
        {ok, Duplicates}
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

%% @doc
%% Merges source party into target party and transfers account ownership.
%%
%% @spec merge_parties(uuid(), uuid(), binary()) -> {ok, #party{}} | {error, atom()}.
merge_parties(SourcePartyId, TargetPartyId, Reason)
        when is_binary(Reason), SourcePartyId =/= TargetPartyId ->
    F = fun() ->
        case {mnesia:read(party, SourcePartyId, write), mnesia:read(party, TargetPartyId, write)} of
            {[], _} ->
                {error, source_party_not_found};
            {_, []} ->
                {error, target_party_not_found};
            {[SourceParty], [TargetParty]} ->
                case {SourceParty#party.status, TargetParty#party.status} of
                    {closed, _} ->
                        {error, source_party_closed};
                    {_, closed} ->
                        {error, target_party_closed};
                    _ ->
                        Accounts = mnesia:index_read(account, SourcePartyId, party_id),
                        lists:foreach(
                            fun(Account) ->
                                UpdatedAccount = Account#account{
                                    party_id = TargetPartyId,
                                    updated_at = erlang:system_time(millisecond)
                                },
                                mnesia:write(UpdatedAccount)
                            end,
                            Accounts
                        ),
                        UpdatedSource = bump_party_version(SourceParty#party{
                            status = closed,
                            merged_into_party_id = TargetPartyId,
                            review_notes = Reason
                        }),
                        mnesia:write(UpdatedSource),
                        write_party_audit(SourcePartyId, merge_into, UpdatedSource#party.version, #{target_party_id => TargetPartyId}),
                        write_party_audit(TargetPartyId, merge_target, TargetParty#party.version, #{source_party_id => SourcePartyId}),
                        {ok, UpdatedSource}
                end
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end;
merge_parties(_, _, _) ->
    {error, invalid_merge_request}.

%% -----------------------------------------------------------------------------
%% Internal helpers
%% -----------------------------------------------------------------------------

-spec bump_party_version(#party{}) -> #party{}.
bump_party_version(Party) ->
    Party#party{
        version = Party#party.version + 1,
        updated_at = erlang:system_time(millisecond)
    }.

-dialyzer({nowarn_function, write_party_audit/4}).
-spec write_party_audit(uuid(), atom(), pos_integer(), map()) -> ok.
write_party_audit(PartyId, Action, Version, Metadata) ->
    Audit = #party_audit{
        audit_id = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
        party_id = PartyId,
        action = Action,
        version = Version,
        metadata = Metadata,
        created_at = erlang:system_time(millisecond)
    },
    mnesia:write(Audit),
    ok.

-spec matches_party_filters(#party{}, map()) -> boolean().
matches_party_filters(Party, Filters) ->
    StatusMatch = case maps:find(status, Filters) of
        {ok, Status} -> Party#party.status =:= Status;
        error -> true
    end,
    EmailMatch = case maps:find(email_contains, Filters) of
        {ok, Contains} when is_binary(Contains) ->
            binary:match(Party#party.email, Contains) =/= nomatch;
        _ ->
            true
    end,
    StatusMatch andalso EmailMatch.

-spec normalize_name(binary()) -> binary().
normalize_name(Name) ->
    Trimmed = string:trim(Name),
    Collapsed = re:replace(Trimmed, <<"\\s+">>, <<" ">>, [global, {return, binary}]),
    list_to_binary(string:lowercase(binary_to_list(Collapsed))).

-spec validate_address(map()) -> ok | {error, invalid_address}.
validate_address(Address) ->
    Required = [line1, city, country],
    case lists:all(
        fun(Key) ->
            case maps:find(Key, Address) of
                {ok, Value} when is_binary(Value), byte_size(Value) > 0 -> true;
                _ -> false
            end
        end,
        Required
    ) of
        true -> ok;
        false -> {error, invalid_address}
    end.

%% @doc Set the risk tier classification for a party.
%%
%% Valid tiers: low | medium | high | critical
%% Records an audit entry for the tier change.
-spec set_risk_tier(uuid(), risk_tier()) ->
    {ok, #party{}} | {error, not_found | invalid_risk_tier}.
set_risk_tier(PartyId, Tier) when
        Tier =:= low orelse Tier =:= medium orelse
        Tier =:= high orelse Tier =:= critical ->
    Now = erlang:system_time(millisecond),
    F = fun() ->
        case mnesia:read(party, PartyId, write) of
            [] -> {error, not_found};
            [Party] ->
                Updated = Party#party{
                    risk_tier  = Tier,
                    version    = Party#party.version + 1,
                    updated_at = Now
                },
                ok = mnesia:write(party, Updated, write),
                AuditId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
                Audit = #party_audit{
                    audit_id   = AuditId,
                    party_id   = PartyId,
                    action     = risk_tier_changed,
                    version    = Updated#party.version,
                    metadata   = #{risk_tier => Tier},
                    created_at = Now
                },
                ok = mnesia:write(party_audit, Audit, write),
                {ok, Updated}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, Reason} -> {error, Reason}
    end;
set_risk_tier(_PartyId, _InvalidTier) ->
    {error, invalid_risk_tier}.

%% @doc Get the risk tier for a party.
-spec get_risk_tier(uuid()) -> {ok, risk_tier()} | {error, not_found}.
get_risk_tier(PartyId) ->
    case mnesia:dirty_read(party, PartyId) of
        [Party] -> {ok, Party#party.risk_tier};
        [] -> {error, not_found}
    end.

%% @doc Return the audit log retention period in days for a given risk tier.
%%
%% Retention policy:
%% - low: 365 days (1 year)
%% - medium: 730 days (2 years)
%% - high: 1825 days (5 years)
%% - critical: 3650 days (10 years)
-dialyzer({nowarn_function, retention_days_for_tier/1}).
-spec retention_days_for_tier(risk_tier()) -> pos_integer().
retention_days_for_tier(low)      -> 365;
retention_days_for_tier(medium)   -> 730;
retention_days_for_tier(high)     -> 1825;
retention_days_for_tier(critical) -> 3650.
