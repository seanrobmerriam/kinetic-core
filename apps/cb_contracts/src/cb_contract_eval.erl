%% @doc Deterministic evaluator for DSL v1 contract rules.
-module(cb_contract_eval).

-export([evaluate/4]).

-spec evaluate(map(), map(), map(), map()) ->
    {ok, map(), map()} | {error, atom(), map()}.
evaluate(Contract, Context, Authz, Trace0) ->
    Params = maps:get(parameters, Contract, #{}),
    Rules = maps:get(rules, Contract, []),
    State0 = #{contract => Contract,
               context => Context,
               params => Params,
               authz => Authz,
               decision => #{},
               trace => Trace0},
    eval_rules(Rules, State0).

eval_rules([], State) ->
    {ok, maps:get(decision, State), maps:get(trace, State)};
eval_rules([Rule | Rest], State0) ->
    CondExpr = map_get_any(Rule, 'when', true),
    case eval_expr(CondExpr, State0) of
        {ok, true} ->
            Actions = map_get_any(Rule, 'then', []),
            case apply_actions(Actions, State0) of
                {ok, State1} -> eval_rules(Rest, State1);
                {error, Reason, State1} -> {error, Reason, maps:get(trace, State1)}
            end;
        {ok, false} ->
            Actions = map_get_any(Rule, 'else', []),
            case apply_actions(Actions, State0) of
                {ok, State1} -> eval_rules(Rest, State1);
                {error, Reason, State1} -> {error, Reason, maps:get(trace, State1)}
            end;
        {error, Reason} ->
            Trace1 = cb_contract_audit:add_step(maps:get(trace, State0),
                                               #{stage => eval_condition_failed,
                                                 reason => Reason}),
            {error, Reason, Trace1}
    end.

apply_actions([], State) ->
    {ok, State};
apply_actions([Action | Rest], State0) ->
    case apply_action(Action, State0) of
        {ok, State1} -> apply_actions(Rest, State1);
        {error, Reason, State1} -> {error, Reason, State1}
    end.

apply_action(Action, State0) when is_map(Action), map_size(Action) =:= 1 ->
    [{OpRaw, Payload}] = maps:to_list(Action),
    Op = norm_key(OpRaw),
    case Op of
        set ->
            case require_capability(can_set_decision_fields, State0) of
                ok ->
                    Path = map_get_any(Payload, path, <<"decision.value">>),
                    Value = map_get_any(Payload, value, undefined),
                    Decision0 = maps:get(decision, State0),
                    Decision1 = maps:put(path_key(Path), Value, Decision0),
                    Trace1 = cb_contract_audit:add_step(maps:get(trace, State0),
                                                       #{stage => action_set,
                                                         path => path_key(Path)}),
                    {ok, State0#{decision => Decision1, trace => Trace1}};
                {error, capability_denied} ->
                    {error, capability_denied, State0}
            end;
        reject ->
            Reason = map_get_any(Payload, reason, <<"contract_rejected">>),
            Trace1 = cb_contract_audit:add_step(maps:get(trace, State0),
                                               #{stage => action_reject,
                                                 reason => Reason}),
            {error, contract_rejected, State0#{trace => Trace1}};
        emit ->
            case require_capability(can_emit_event, State0) of
                ok ->
                    Event = #{event => map_get_any(Payload, event, <<"contract.event">>),
                              severity => map_get_any(Payload, severity, <<"info">>)},
                    Trace1 = cb_contract_audit:add_event(maps:get(trace, State0), Event),
                    {ok, State0#{trace => Trace1}};
                {error, capability_denied} ->
                    {error, capability_denied, State0}
            end;
        enqueue_review ->
            case require_capability(can_enqueue_review, State0) of
                ok ->
                    Decision0 = maps:get(decision, State0),
                    Queue = map_get_any(Payload, queue, <<"manual_review">>),
                    Decision1 = Decision0#{status => <<"manual_review">>, review_queue => Queue},
                    Trace1 = cb_contract_audit:add_step(maps:get(trace, State0),
                                                       #{stage => action_enqueue_review,
                                                         queue => Queue}),
                    {ok, State0#{decision => Decision1, trace => Trace1}};
                {error, capability_denied} ->
                    {error, capability_denied, State0}
            end;
        _ ->
            {error, forbidden_operator, State0}
    end;
apply_action(_Action, State) ->
    {error, invalid_contract_schema, State}.

require_capability(Capability, State) ->
    Authz = maps:get(authz, State, #{}),
    Caps = maps:get(capabilities, Authz, []),
    case lists:member(Capability, Caps) of
        true -> ok;
        false -> {error, capability_denied}
    end.

eval_expr(Expr, _State) when is_boolean(Expr); is_integer(Expr); is_binary(Expr) ->
    {ok, Expr};
eval_expr(Expr, _State) when is_list(Expr), Expr =:= [] ->
    {ok, Expr};
eval_expr(Expr, State) when is_map(Expr) ->
    case {map_find_any(Expr, var), map_find_any(Expr, param)} of
        {{ok, Path}, _} ->
            lookup_var(Path, maps:get(context, State, #{}));
        {_, {ok, Name}} ->
            lookup_param(Name, maps:get(params, State, #{}));
        _ ->
            eval_operator_map(Expr, State)
    end;
eval_expr(_Expr, _State) ->
    {error, type_mismatch}.

eval_operator_map(Expr, State) when map_size(Expr) =:= 1 ->
    [{OpRaw, Args}] = maps:to_list(Expr),
    Op = norm_key(OpRaw),
    eval_operator(Op, Args, State);
eval_operator_map(_Expr, _State) ->
    {error, invalid_contract_schema}.

eval_operator('and', Args, State) when is_list(Args) ->
    eval_bool_fold(Args, true, fun(A, B) -> A andalso B end, State);
eval_operator('or', Args, State) when is_list(Args) ->
    eval_bool_fold(Args, false, fun(A, B) -> A orelse B end, State);
eval_operator('not', Arg, State) ->
    case eval_expr(Arg, State) of
        {ok, B} when is_boolean(B) -> {ok, not B};
        _ -> {error, type_mismatch}
    end;
eval_operator('==', Args, State) -> eval_compare(Args, fun(A, B) -> A =:= B end, State);
eval_operator('!=', Args, State) -> eval_compare(Args, fun(A, B) -> A =/= B end, State);
eval_operator('<', Args, State) -> eval_compare(Args, fun(A, B) -> A < B end, State);
eval_operator('=<', Args, State) -> eval_compare(Args, fun(A, B) -> A =< B end, State);
eval_operator('>', Args, State) -> eval_compare(Args, fun(A, B) -> A > B end, State);
eval_operator('>=', Args, State) -> eval_compare(Args, fun(A, B) -> A >= B end, State);
eval_operator('+', Args, State) -> eval_arith(Args, fun(A, B) -> A + B end, State);
eval_operator('-', Args, State) -> eval_arith(Args, fun(A, B) -> A - B end, State);
eval_operator('*', Args, State) -> eval_arith(Args, fun(A, B) -> A * B end, State);
eval_operator('div', Args, State) ->
    eval_arith(Args,
               fun(_A, 0) -> error(badarith);
                  (A, B) -> A div B
               end,
               State);
eval_operator('mod', Args, State) ->
    eval_arith(Args,
               fun(_A, 0) -> error(badarith);
                  (A, B) -> A rem B
               end,
               State);
eval_operator('in', Args, State) when is_list(Args), length(Args) =:= 2 ->
    [NeedleExpr, HayExpr] = Args,
    case {eval_expr(NeedleExpr, State), eval_expr(HayExpr, State)} of
        {{ok, Needle}, {ok, Hay}} when is_list(Hay) -> {ok, lists:member(Needle, Hay)};
        _ -> {error, type_mismatch}
    end;
eval_operator(_Op, _Args, _State) ->
    {error, forbidden_operator}.

eval_bool_fold([], Acc, _Fun, _State) ->
    {ok, Acc};
eval_bool_fold([Expr | Rest], Acc, Fun, State) ->
    case eval_expr(Expr, State) of
        {ok, B} when is_boolean(B) ->
            eval_bool_fold(Rest, Fun(Acc, B), Fun, State);
        _ ->
            {error, type_mismatch}
    end.

eval_compare(Args, Fun, State) when is_list(Args), length(Args) =:= 2 ->
    [AExpr, BExpr] = Args,
    case {eval_expr(AExpr, State), eval_expr(BExpr, State)} of
        {{ok, A}, {ok, B}} -> {ok, Fun(A, B)};
        _ -> {error, type_mismatch}
    end;
eval_compare(_Args, _Fun, _State) ->
    {error, invalid_contract_schema}.

eval_arith(Args, Fun, State) when is_list(Args), length(Args) =:= 2 ->
    [AExpr, BExpr] = Args,
    case {eval_expr(AExpr, State), eval_expr(BExpr, State)} of
        {{ok, A}, {ok, B}} when is_integer(A), is_integer(B) ->
            try {ok, Fun(A, B)}
            catch
                error:badarith -> {error, type_mismatch}
            end;
        _ ->
            {error, type_mismatch}
    end;
eval_arith(_Args, _Fun, _State) ->
    {error, invalid_contract_schema}.

lookup_var(Path, Context) ->
    Keys = path_segments(Path),
    lookup_path(Keys, Context).

lookup_param(Name, Params) ->
    case map_find_any(Params, Name) of
        {ok, Val} -> {ok, Val};
        error -> {error, unknown_variable_path}
    end.

lookup_path([], Value) ->
    {ok, Value};
lookup_path([K | Rest], Value) when is_map(Value) ->
    case map_find_any(Value, K) of
        {ok, Next} -> lookup_path(Rest, Next);
        error -> {error, unknown_variable_path}
    end;
lookup_path(_Keys, _Value) ->
    {error, unknown_variable_path}.

path_segments(Path) when is_binary(Path) ->
    [list_to_binary(S) || S <- string:tokens(binary_to_list(Path), ".")];
path_segments(Path) when is_list(Path) ->
    [list_to_binary(S) || S <- string:tokens(Path, ".")];
path_segments(Path) when is_atom(Path) ->
    [atom_to_binary(Path, utf8)].

path_key(Path) when is_binary(Path) -> Path;
path_key(Path) when is_list(Path) -> list_to_binary(Path);
path_key(Path) when is_atom(Path) -> atom_to_binary(Path, utf8).

map_find_any(Map, Key) when is_map(Map), is_atom(Key) ->
    BKey = atom_to_binary(Key, utf8),
    case maps:find(Key, Map) of
        {ok, Val} -> {ok, Val};
        error -> maps:find(BKey, Map)
    end;
map_find_any(Map, Key) when is_map(Map), is_binary(Key) ->
    AKey = maybe_existing_atom(Key),
    case maps:find(Key, Map) of
        {ok, Val} -> {ok, Val};
        error when AKey =/= undefined -> maps:find(AKey, Map);
        error -> error
    end;
map_find_any(Map, Key) when is_map(Map), is_list(Key) ->
    map_find_any(Map, list_to_binary(Key)).

map_get_any(Map, Key, Default) ->
    case map_find_any(Map, Key) of
        {ok, Val} -> Val;
        error -> Default
    end.

maybe_existing_atom(KeyBin) ->
    try binary_to_existing_atom(KeyBin, utf8)
    catch
        error:badarg -> undefined
    end.

norm_key(K) when is_atom(K) -> K;
norm_key(K) when is_binary(K) ->
    case K of
        <<"and">> -> 'and';
        <<"or">> -> 'or';
        <<"not">> -> 'not';
        <<"==">> -> '==';
        <<"!=">> -> '!=';
        <<"<">> -> '<';
        <<"<=">> -> '=<';
        <<">">> -> '>';
        <<">=">> -> '>=';
        <<"+">> -> '+';
        <<"-">> -> '-';
        <<"*">> -> '*';
        <<"div">> -> 'div';
        <<"mod">> -> 'mod';
        <<"in">> -> 'in';
        <<"set">> -> set;
        <<"reject">> -> reject;
        <<"emit">> -> emit;
        <<"enqueue_review">> -> enqueue_review;
        _ -> unknown
    end;
norm_key(K) when is_list(K) ->
    norm_key(list_to_binary(K)).
