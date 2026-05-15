%% @doc Bounded evaluator execution wrapper.
-module(cb_contract_sandbox).

-export([run/2]).

-spec run(fun(() -> term()), pos_integer()) ->
    {ok, term(), non_neg_integer()} |
    {error, atom() | tuple(), non_neg_integer()}.
run(Fun, TimeoutMs) when is_function(Fun, 0), is_integer(TimeoutMs), TimeoutMs > 0 ->
    StartUs = erlang:monotonic_time(microsecond),
    Parent = self(),
    ReplyRef = make_ref(),
    {Pid, MonRef} = spawn_monitor(
        fun() ->
            Parent ! {ReplyRef, safe_call(Fun)}
        end),
    receive
        {ReplyRef, Result} ->
            erlang:demonitor(MonRef, [flush]),
            {ok, Result, elapsed_us(StartUs)};
        {'DOWN', MonRef, process, _Pid, Reason} ->
            {error, {sandbox_crash, Reason}, elapsed_us(StartUs)}
    after TimeoutMs ->
            exit(Pid, kill),
            receive
                {'DOWN', MonRef, process, _Pid2, _Reason2} -> ok
            after 0 ->
                ok
            end,
            {error, execution_budget_exceeded, elapsed_us(StartUs)}
    end.

safe_call(Fun) ->
    try Fun() of
        Value -> Value
    catch
        Class:Reason:Stack ->
            {error, {Class, Reason, Stack}}
    end.

elapsed_us(StartUs) ->
    erlang:monotonic_time(microsecond) - StartUs.
