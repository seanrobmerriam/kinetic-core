%% @doc STP pipeline metrics and reporting (TASK-053).
%%
%% All functions query Mnesia directly and are intentionally stateless — no
%% gen_server is required.  Metrics are computed on demand.
%%
%% Key metrics:
%% - stp_rate/0              — overall straight-through vs exception counts
%% - exception_reasons/0     — breakdown of exception queue items by reason
%% - sla_compliance/0        — fraction of resolved items that met their SLA
%% - recent_activity/1       — last N payment orders with their STP outcome
-module(cb_stp_metrics).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    stp_rate/0,
    exception_reasons/0,
    sla_compliance/0,
    recent_activity/1
]).

%%% --------------------------------------------------------------- API ----

%% @doc Compute overall STP throughput statistics.
%%
%% Returns a map with:
%% - `total'            — total payment orders processed
%% - `straight_through' — count auto-approved
%% - `exception'        — count routed to exception queue
%% - `rate_bps'         — straight-through rate in basis points (0–10_000)
-spec stp_rate() -> #{
    total            := non_neg_integer(),
    straight_through := non_neg_integer(),
    exception        := non_neg_integer(),
    rate_bps         := non_neg_integer()
}.
stp_rate() ->
    AllOrders = mnesia:dirty_match_object(payment_order,
                                          #payment_order{_ = '_'}),
    Total = length(AllOrders),
    Exceptions = length(mnesia:dirty_match_object(exception_item,
                                                   #exception_item{_ = '_'})),
    StraightThrough = max(0, Total - Exceptions),
    RateBps = case Total of
        0 -> 0;
        _ -> (StraightThrough * 10_000) div Total
    end,
    #{
        total            => Total,
        straight_through => StraightThrough,
        exception        => Exceptions,
        rate_bps         => RateBps
    }.

%% @doc Tally exception items grouped by reason string.
%%
%% Returns a list of `{Reason, Count}' pairs sorted by descending count.
-spec exception_reasons() -> [{binary(), pos_integer()}].
exception_reasons() ->
    Items = mnesia:dirty_match_object(exception_item,
                                      #exception_item{_ = '_'}),
    Tally = lists:foldl(fun(Item, Acc) ->
        Reason = Item#exception_item.reason,
        maps:update_with(Reason, fun(N) -> N + 1 end, 1, Acc)
    end, #{}, Items),
    Pairs = maps:to_list(Tally),
    lists:sort(fun({_, A}, {_, B}) -> A >= B end, Pairs).

%% @doc Compute SLA compliance rate across resolved exception items.
%%
%% An item is "compliant" if it was resolved before `sla_deadline' (or
%% had no SLA).  Items that still have `status = pending' are excluded.
%%
%% Returns a map with `total_resolved', `within_sla', `rate_bps'.
-spec sla_compliance() -> #{
    total_resolved := non_neg_integer(),
    within_sla     := non_neg_integer(),
    rate_bps       := non_neg_integer()
}.
sla_compliance() ->
    Resolved = [I || I <- mnesia:dirty_match_object(exception_item,
                                                      #exception_item{_ = '_'}),
                     I#exception_item.status =/= pending],
    TotalResolved = length(Resolved),
    WithinSla = length([I || I <- Resolved, sla_met(I)]),
    RateBps = case TotalResolved of
        0 -> 10_000;
        _ -> (WithinSla * 10_000) div TotalResolved
    end,
    #{
        total_resolved => TotalResolved,
        within_sla     => WithinSla,
        rate_bps       => RateBps
    }.

%% @doc Return the N most recently created payment orders with STP metadata.
%%
%% Each entry is a map with keys:
%% `payment_id', `amount', `currency', `status', `created_at',
%% `exception_reason' (binary or `null').
-spec recent_activity(pos_integer()) -> [map()].
recent_activity(N) when is_integer(N), N > 0 ->
    AllOrders = mnesia:dirty_match_object(payment_order,
                                          #payment_order{_ = '_'}),
    Sorted = lists:sort(fun(A, B) ->
        A#payment_order.created_at >= B#payment_order.created_at
    end, AllOrders),
    Recent = lists:sublist(Sorted, N),
    ExItems = mnesia:dirty_match_object(exception_item,
                                         #exception_item{_ = '_'}),
    ExByPayment = lists:foldl(fun(I, Acc) ->
        maps:put(I#exception_item.payment_id, I#exception_item.reason, Acc)
    end, #{}, ExItems),
    lists:map(fun(Order) ->
        #{
            payment_id       => Order#payment_order.payment_id,
            amount           => Order#payment_order.amount,
            currency         => Order#payment_order.currency,
            status           => Order#payment_order.status,
            created_at       => Order#payment_order.created_at,
            exception_reason => maps:get(Order#payment_order.payment_id,
                                         ExByPayment, null)
        }
    end, Recent).

%%% ---------------------------------------------------------- INTERNALS ---

-spec sla_met(#exception_item{}) -> boolean().
sla_met(Item) ->
    case Item#exception_item.sla_deadline of
        undefined ->
            true;
        Deadline ->
            Item#exception_item.updated_at =< Deadline
    end.
