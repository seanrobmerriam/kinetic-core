%% @doc Static contract validation and safety checks for DSL v1.
-module(cb_contract_validator).

-export([validate_contract/1]).

-define(MAX_CONTRACT_BYTES, 131072).
-define(MAX_RULES, 200).
-define(MAX_EXPR_DEPTH, 16).

-spec validate_contract(map()) -> {ok, map()} | {error, atom()}.
validate_contract(Contract) when is_map(Contract) ->
    case validate_size(Contract) of
        ok ->
            case validate_version(Contract) of
                ok ->
                    case get_map(Contract, trigger) of
                        {ok, _Trigger} ->
                            validate_rules(Contract);
                        error ->
                            {error, invalid_contract_schema}
                    end;
                ErrorV ->
                    ErrorV
            end;
        ErrorS ->
            ErrorS
    end;
validate_contract(_) ->
    {error, invalid_contract_schema}.

validate_size(Contract) ->
    case byte_size(term_to_binary(Contract)) =< ?MAX_CONTRACT_BYTES of
        true -> ok;
        false -> {error, invalid_contract_schema}
    end.

validate_version(Contract) ->
    case get_any(Contract, dsl_version) of
        {ok, <<"1.0">>} -> ok;
        {ok, "1.0"} -> ok;
        _ -> {error, unsupported_dsl_version}
    end.

validate_rules(Contract) ->
    case get_list(Contract, rules) of
        {ok, Rules} when length(Rules) =< ?MAX_RULES ->
            case validate_rule_list(Rules) of
                ok -> {ok, Contract};
                {error, _} = Error -> Error
            end;
        {ok, _RulesTooMany} ->
            {error, invalid_contract_schema};
        error ->
            {error, invalid_contract_schema}
    end.

validate_rule_list([]) ->
    ok;
validate_rule_list([Rule | Rest]) ->
    case validate_rule(Rule) of
        ok -> validate_rule_list(Rest);
        {error, _} = Error -> Error
    end.

validate_rule(Rule) when is_map(Rule) ->
    case get_any(Rule, when) of
        {ok, CondExpr} ->
            case expr_depth(CondExpr) =< ?MAX_EXPR_DEPTH of
                true ->
                    case validate_expr(CondExpr) of
                        ok ->
                            validate_actions_field(Rule, then);
                        Error ->
                            Error
                    end;
                false ->
                    {error, invalid_contract_schema}
            end;
        error ->
            {error, invalid_contract_schema}
    end;
validate_rule(_) ->
    {error, invalid_contract_schema}.

validate_actions_field(Rule, Key) ->
    case get_any(Rule, Key) of
        {ok, Actions} when is_list(Actions) ->
            validate_actions(Actions);
        {ok, _Other} ->
            {error, invalid_contract_schema};
        error when Key =:= else ->
            ok;
        error ->
            {error, invalid_contract_schema}
    end.

validate_actions([]) ->
    ok;
validate_actions([Action | Rest]) when is_map(Action), map_size(Action) =:= 1 ->
    [{OpRaw, Payload}] = maps:to_list(Action),
    Op = norm_key(OpRaw),
    case lists:member(Op, [set, reject, emit, enqueue_review]) of
        true ->
            case is_map(Payload) of
                true -> validate_actions(Rest);
                false -> {error, invalid_contract_schema}
            end;
        false ->
            {error, forbidden_operator}
    end;
validate_actions(_) ->
    {error, invalid_contract_schema}.

validate_expr(Expr) when is_boolean(Expr); is_integer(Expr); is_binary(Expr); is_list(Expr) ->
    ok;
validate_expr(Expr) when is_map(Expr) ->
    case {get_any(Expr, var), get_any(Expr, param)} of
        {{ok, Path}, _} when is_binary(Path); is_list(Path) ->
            ok;
        {_, {ok, Name}} when is_binary(Name); is_list(Name); is_atom(Name) ->
            ok;
        _ ->
            case map_size(Expr) =:= 1 of
                true ->
                    [{OpRaw, Args}] = maps:to_list(Expr),
                    Op = norm_key(OpRaw),
                    case lists:member(Op, [and, or, not, '==', '!=', '<', '=<', '>', '>=', '+', '-', '*', div, mod, in]) of
                        true -> validate_expr_args(Args);
                        false -> {error, forbidden_operator}
                    end;
                false ->
                    {error, invalid_contract_schema}
            end
    end;
validate_expr(_) ->
    {error, type_mismatch}.

validate_expr_args(Args) when is_list(Args) ->
    validate_expr_list(Args);
validate_expr_args(Arg) ->
    validate_expr(Arg).

validate_expr_list([]) ->
    ok;
validate_expr_list([Expr | Rest]) ->
    case validate_expr(Expr) of
        ok -> validate_expr_list(Rest);
        Error -> Error
    end.

expr_depth(Expr) when is_map(Expr) ->
    Depths = [expr_depth(V) || {_K, V} <- maps:to_list(Expr)],
    1 + max_or_zero(Depths);
expr_depth(Expr) when is_list(Expr) ->
    Depths = [expr_depth(V) || V <- Expr],
    1 + max_or_zero(Depths);
expr_depth(_) ->
    1.

max_or_zero([]) -> 0;
max_or_zero(List) -> lists:max(List).

get_map(Map, Key) when is_map(Map) ->
    case get_any(Map, Key) of
        {ok, Val} when is_map(Val) -> {ok, Val};
        _ -> error
    end.

get_list(Map, Key) when is_map(Map) ->
    case get_any(Map, Key) of
        {ok, Val} when is_list(Val) -> {ok, Val};
        _ -> error
    end.

get_any(Map, Key) ->
    BKey = atom_to_binary(Key, utf8),
    case maps:find(Key, Map) of
        {ok, Val} -> {ok, Val};
        error -> maps:find(BKey, Map)
    end.

norm_key(K) when is_atom(K) -> K;
norm_key(K) when is_binary(K) ->
    case K of
        <<"and">> -> and;
        <<"or">> -> or;
        <<"not">> -> not;
        <<"==">> -> '==';
        <<"!=">> -> '!=';
        <<"<">> -> '<';
        <<"<=">> -> '=<';
        <<">">> -> '>';
        <<">=">> -> '>=';
        <<"+">> -> '+';
        <<"-">> -> '-';
        <<"*">> -> '*';
        <<"div">> -> div;
        <<"mod">> -> mod;
        <<"in">> -> in;
        <<"set">> -> set;
        <<"reject">> -> reject;
        <<"emit">> -> emit;
        <<"enqueue_review">> -> enqueue_review;
        _ -> unknown
    end;
norm_key(K) when is_list(K) ->
    norm_key(list_to_binary(K)).
