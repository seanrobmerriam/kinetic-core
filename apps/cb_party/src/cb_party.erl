-module(cb_party).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    create_party/2,
    get_party/1,
    list_parties/2,
    suspend_party/1,
    close_party/1
]).

%% @doc Create a new party.
-spec create_party(binary(), binary()) -> {ok, #party{}} | {error, atom()}.
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
                    created_at = Now,
                    updated_at = Now
                },
                mnesia:write(Party),
                {ok, Party};
            [_Existing] ->
                {error, email_already_exists}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _Reason} -> {error, database_error}
    end.

%% @doc Get a party by ID.
-spec get_party(uuid()) -> {ok, #party{}} | {error, atom()}.
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

%% @doc List all parties with pagination.
-spec list_parties(pos_integer(), pos_integer()) ->
    {ok, #{items => [#party{}], total => non_neg_integer(), page => pos_integer(), page_size => pos_integer()}} |
    {error, atom()}.
list_parties(Page, PageSize) when Page >= 1, PageSize >= 1, PageSize =< 100 ->
    F = fun() ->
        AllParties = mnesia:match_object(party, #party{_ = '_'}, read),
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

%% @doc Suspend a party.
-spec suspend_party(uuid()) -> {ok, #party{}} | {error, atom()}.
suspend_party(PartyId) ->
    F = fun() ->
        case mnesia:read(party, PartyId, write) of
            [Party] ->
                case Party#party.status of
                    active ->
                        Now = erlang:system_time(millisecond),
                        Updated = Party#party{status = suspended, updated_at = Now},
                        mnesia:write(Updated),
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

%% @doc Close a party. Party must have no active accounts.
-spec close_party(uuid()) -> {ok, #party{}} | {error, atom()}.
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
                                Now = erlang:system_time(millisecond),
                                Updated = Party#party{status = closed, updated_at = Now},
                                mnesia:write(Updated),
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
