%% @doc Execution trace helper for contract runs.
-module(cb_contract_audit).

-include_lib("cb_contracts/include/cb_contracts.hrl").

-export([
    new_trace/3,
    add_step/2,
    add_event/2,
    finish_ok/2,
    finish_error/2,
    persist_trace/1
]).

-define(MAX_STEPS, 500).

-spec new_trace(map(), map(), term()) -> map().
new_trace(Contract, Context, RequestId) ->
    StartedAtUs = erlang:system_time(microsecond),
    #{execution_id => new_id(),
      contract_id => maps:get(contract_id, Contract, undefined),
      contract_version => maps:get(version, Contract, maps:get(dsl_version, Contract, <<"1.0">>)),
      request_id => RequestId,
      input_hash => hash_term(Context),
      started_at_us => StartedAtUs,
      finished_at_us => undefined,
      duration_us => undefined,
      result => running,
      reason => undefined,
      decision_hash => undefined,
    context_snapshot => Context,
    decision_snapshot => undefined,
      steps => [],
      events => []}.

-spec add_step(map(), map()) -> map().
add_step(Trace, Step) ->
    Steps0 = maps:get(steps, Trace, []),
    Steps1 = [Step | Steps0],
    Trace#{steps => trim(Steps1)}.

-spec add_event(map(), map()) -> map().
add_event(Trace, Event) ->
    Events0 = maps:get(events, Trace, []),
    Events1 = [Event | Events0],
    Trace#{events => trim(Events1)}.

-spec finish_ok(map(), map()) -> map().
finish_ok(Trace, Decision) ->
    finish(Trace, ok, undefined, Decision).

-spec finish_error(map(), atom()) -> map().
finish_error(Trace, Reason) ->
    finish(Trace, error, Reason, undefined).

-spec persist_trace(map()) -> ok.
persist_trace(Trace) ->
    Rec = #contract_execution_trace{
        execution_id = maps:get(execution_id, Trace),
        contract_id = maps:get(contract_id, Trace, undefined),
        contract_version = maps:get(contract_version, Trace, undefined),
        request_id = maps:get(request_id, Trace, undefined),
        input_hash = maps:get(input_hash, Trace, <<>>),
        decision_hash = maps:get(decision_hash, Trace, undefined),
        result = maps:get(result, Trace, error),
        reason = maps:get(reason, Trace, undefined),
        started_at_us = maps:get(started_at_us, Trace, 0),
        finished_at_us = maps:get(finished_at_us, Trace, undefined),
        duration_us = maps:get(duration_us, Trace, undefined),
        context_snapshot = maps:get(context_snapshot, Trace, #{}),
        decision_snapshot = maps:get(decision_snapshot, Trace, undefined),
        trace_payload = Trace,
        created_at = erlang:system_time(millisecond)
    },
    case mnesia:transaction(fun() -> mnesia:write(Rec) end) of
        {atomic, ok} -> ok;
        _ -> ok
    end.

finish(Trace, Result, Reason, Decision) ->
    FinishedAtUs = erlang:system_time(microsecond),
    StartedAtUs = maps:get(started_at_us, Trace, FinishedAtUs),
    DecisionHash = case Decision of
        undefined -> undefined;
        _ -> hash_term(Decision)
    end,
    Trace#{finished_at_us => FinishedAtUs,
           duration_us => FinishedAtUs - StartedAtUs,
           result => Result,
           reason => Reason,
           decision_hash => DecisionHash,
            decision_snapshot => Decision,
           steps => lists:reverse(maps:get(steps, Trace, [])),
           events => lists:reverse(maps:get(events, Trace, []))}.

trim(List) when length(List) =< ?MAX_STEPS ->
    List;
trim(List) ->
    lists:sublist(List, ?MAX_STEPS).

hash_term(Term) ->
    Bin = crypto:hash(sha256, term_to_binary(Term)),
    iolist_to_binary([io_lib:format("~2.16.0b", [B]) || <<B>> <= Bin]).

new_id() ->
    uuid:uuid_to_string(uuid:get_v4(), binary_standard).
