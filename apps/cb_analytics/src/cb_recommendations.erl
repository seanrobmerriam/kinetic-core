%%%-------------------------------------------------------------------
%% @doc Product recommendations (P5-S1, TASK-075).
%%
%% Persists scored recommendations with rationale and a status lifecycle:
%% pending -> delivered -> (accepted | dismissed). Compliance review can
%% inspect the rationale at any time.
%% @end
%%%-------------------------------------------------------------------
-module(cb_recommendations).

-include_lib("cb_ledger/include/cb_ledger.hrl").
-include_lib("cb_analytics/include/cb_analytics.hrl").

-export([
    create/4,
    list_for_party/1,
    list_pending/0,
    transition/2,
    get/1
]).

-spec create(uuid(), binary(), float(), binary()) ->
    {ok, uuid()} | {error, invalid_score}.
create(_PartyId, _ProductCode, Score, _Rationale)
        when Score < 0.0; Score > 1.0 ->
    {error, invalid_score};
create(PartyId, ProductCode, Score, Rationale) ->
    Id = new_id(),
    Now = now_ms(),
    R = #product_recommendation{
        recommendation_id = Id,
        party_id          = PartyId,
        product_code      = ProductCode,
        score             = Score,
        rationale         = Rationale,
        status            = pending,
        created_at        = Now,
        updated_at        = Now
    },
    {atomic, ok} = mnesia:transaction(fun() -> mnesia:write(R) end),
    {ok, Id}.

-spec list_for_party(uuid()) -> [#product_recommendation{}].
list_for_party(PartyId) ->
    {atomic, L} = mnesia:transaction(fun() ->
        mnesia:index_read(product_recommendation, PartyId, party_id)
    end),
    L.

-spec list_pending() -> [#product_recommendation{}].
list_pending() ->
    {atomic, L} = mnesia:transaction(fun() ->
        mnesia:index_read(product_recommendation, pending, status)
    end),
    L.

-spec get(uuid()) -> {ok, #product_recommendation{}} | {error, not_found}.
get(Id) ->
    case mnesia:transaction(fun() -> mnesia:read(product_recommendation, Id) end) of
        {atomic, [R]} -> {ok, R};
        {atomic, []}  -> {error, not_found}
    end.

-spec transition(uuid(), recommendation_status()) ->
    ok | {error, not_found | invalid_transition}.
transition(Id, NewStatus) ->
    F = fun() ->
        case mnesia:read(product_recommendation, Id) of
            [] ->
                {error, not_found};
            [R] ->
                case allowed(R#product_recommendation.status, NewStatus) of
                    true ->
                        mnesia:write(R#product_recommendation{
                            status     = NewStatus,
                            updated_at = now_ms()
                        });
                    false ->
                        {error, invalid_transition}
                end
        end
    end,
    case mnesia:transaction(F) of
        {atomic, ok}                            -> ok;
        {atomic, {error, not_found}}            -> {error, not_found};
        {atomic, {error, invalid_transition}}   -> {error, invalid_transition}
    end.

%% Lifecycle: pending -> delivered -> {accepted | dismissed}.
%% pending may also be dismissed directly (e.g. compliance veto).
allowed(pending,   delivered) -> true;
allowed(pending,   dismissed) -> true;
allowed(delivered, accepted)  -> true;
allowed(delivered, dismissed) -> true;
allowed(_,         _)         -> false.

new_id() ->
    uuid:uuid_to_string(uuid:get_v4(), binary_standard).

now_ms() ->
    erlang:system_time(millisecond).
