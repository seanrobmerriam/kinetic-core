%% @doc Account Holds Module
%%
%% Manages temporary holds placed on account funds. A hold reserves a portion
%% of an account's balance, reducing the available balance without reducing the
%% ledger balance.
%%
%% Available balance = account.balance - SUM(amount of active holds)
%%
%% Holds are used for:
%% - Pending payment authorizations
%% - Regulatory or compliance holds
%% - Fraud investigation restrictions
%%
%% @see cb_accounts

-module(cb_account_holds).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    place_hold/4,
    release_hold/1,
    expire_holds/1,
    list_holds/1,
    get_available_balance/1
]).

%% =============================================================================
%% Public API
%% =============================================================================

%% @doc Place a hold on an account for the specified amount.
%%
%% Creates a new active hold on the account. The hold immediately reduces the
%% available balance. The ledger balance is not affected.
%%
%% @param AccountId The account to place the hold on
%% @param Amount The amount to hold in minor units (must be > 0)
%% @param Reason Human-readable reason for the hold
%% @param ExpiresAt Optional expiry timestamp in ms; pass `undefined` for no expiry
%% @returns `{ok, #account_hold{}}` on success, `{error, atom()}` on failure
%%
-spec place_hold(uuid(), amount(), binary(), timestamp_ms() | undefined) ->
    {ok, #account_hold{}} | {error, atom()}.
place_hold(AccountId, Amount, Reason, ExpiresAt)
        when is_binary(AccountId), is_integer(Amount), Amount > 0, is_binary(Reason) ->
    F = fun() ->
        case mnesia:read(account, AccountId) of
            [] ->
                {error, account_not_found};
            [Account] ->
                case Account#account.status of
                    closed ->
                        {error, account_closed};
                    _ ->
                        Now = erlang:system_time(millisecond),
                        HoldId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
                        Hold = #account_hold{
                            hold_id     = HoldId,
                            account_id  = AccountId,
                            amount      = Amount,
                            reason      = Reason,
                            status      = active,
                            placed_at   = Now,
                            released_at = undefined,
                            expires_at  = ExpiresAt
                        },
                        mnesia:write(Hold),
                        {ok, Hold}
                end
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _}     -> {error, database_error}
    end;
place_hold(_, Amount, _, _) when is_integer(Amount), Amount =< 0 ->
    {error, zero_amount};
place_hold(_, _, _, _) ->
    {error, invalid_parameters}.

%% @doc Release an active hold, making the funds available again.
%%
%% Transitions the hold from `active` to `released` and records the
%% release timestamp.
%%
%% @param HoldId The unique identifier of the hold to release
%% @returns `{ok, #account_hold{}}` on success, `{error, atom()}` on failure
%%
-spec release_hold(uuid()) -> {ok, #account_hold{}} | {error, atom()}.
release_hold(HoldId) when is_binary(HoldId) ->
    F = fun() ->
        case mnesia:read(account_hold, HoldId, write) of
            [] ->
                {error, hold_not_found};
            [Hold] ->
                case Hold#account_hold.status of
                    active ->
                        Now = erlang:system_time(millisecond),
                        Updated = Hold#account_hold{
                            status      = released,
                            released_at = Now
                        },
                        mnesia:write(Updated),
                        {ok, Updated};
                    released ->
                        {error, hold_already_released};
                    expired ->
                        {error, hold_already_expired}
                end
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _}     -> {error, database_error}
    end.

%% @doc Expire all active holds on an account that have passed their expiry time.
%%
%% Scans all active holds for the account and transitions any where
%% `expires_at =< now` to `expired` status.
%%
%% @param AccountId The account whose holds should be checked for expiry
%% @returns `{ok, non_neg_integer()}` with the count of expired holds
%%
-spec expire_holds(uuid()) -> {ok, non_neg_integer()}.
expire_holds(AccountId) when is_binary(AccountId) ->
    F = fun() ->
        Holds = mnesia:index_read(account_hold, AccountId, account_id),
        Now = erlang:system_time(millisecond),
        ExpiredCount = lists:foldl(fun(Hold, Acc) ->
            case Hold#account_hold.status =:= active andalso
                 Hold#account_hold.expires_at =/= undefined andalso
                 Hold#account_hold.expires_at =< Now of
                true ->
                    Updated = Hold#account_hold{
                        status      = expired,
                        released_at = Now
                    },
                    mnesia:write(Updated),
                    Acc + 1;
                false ->
                    Acc
            end
        end, 0, Holds),
        {ok, ExpiredCount}
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _}     -> {ok, 0}
    end.

%% @doc List all holds for an account.
%%
%% Returns all holds (active, released, and expired) for the given account,
%% sorted by placement time (newest first).
%%
%% @param AccountId The account to list holds for
%% @returns `{ok, [#account_hold{}]}` on success
%%
-spec list_holds(uuid()) -> {ok, [#account_hold{}]} | {error, atom()}.
list_holds(AccountId) when is_binary(AccountId) ->
    F = fun() ->
        case mnesia:read(account, AccountId) of
            [] ->
                {error, account_not_found};
            _ ->
                Holds = mnesia:index_read(account_hold, AccountId, account_id),
                Sorted = lists:sort(
                    fun(A, B) -> A#account_hold.placed_at >= B#account_hold.placed_at end,
                    Holds
                ),
                {ok, Sorted}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _}     -> {error, database_error}
    end.

%% @doc Compute the available balance for an account (ledger balance minus active holds).
%%
%% First expires any holds that have passed their expiry time, then computes:
%%   available_balance = account.balance - SUM(amount of active holds)
%%
%% @param AccountId The account to compute available balance for
%% @returns `{ok, amount()}` on success, `{error, atom()}` on failure
%%
-spec get_available_balance(uuid()) -> {ok, amount()} | {error, atom()}.
get_available_balance(AccountId) when is_binary(AccountId) ->
    %% Expire stale holds first
    _ = expire_holds(AccountId),
    F = fun() ->
        case mnesia:read(account, AccountId) of
            [] ->
                {error, account_not_found};
            [Account] ->
                HoldTotal = sum_active_holds(AccountId),
                AvailBal = Account#account.balance - HoldTotal,
                {ok, AvailBal}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, _}     -> {error, database_error}
    end.

%% =============================================================================
%% Internal Helpers
%% =============================================================================

%% @private Sum amounts of all active holds for an account.
%% Must be called from within a Mnesia transaction.
-spec sum_active_holds(uuid()) -> non_neg_integer().
sum_active_holds(AccountId) ->
    Holds = mnesia:index_read(account_hold, AccountId, account_id),
    lists:sum([H#account_hold.amount || H <- Holds, H#account_hold.status =:= active]).
