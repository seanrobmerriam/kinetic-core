%% @doc Structured log aggregation, search, retention, and export.
-module(cb_structured_logs).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    write/2,
    search/1,
    export_csv/1,
    get_retention_policy/0,
    set_retention_policy/1,
    apply_retention/0,
    entry_to_map/1
]).

-define(TABLE, structured_log).
-define(RETENTION_TABLE, audit_retention_policy).
-define(RETENTION_RESOURCE, structured_log).
-define(DEFAULT_LIMIT, 100).
-define(DEFAULT_EXPORT_LIMIT, 1000).
-define(DEFAULT_RETENTION_DAYS, 30).

-type log_filters() :: #{}.

-spec write(atom(), map()) -> ok | {error, term()}.
write(Level, Fields) when is_atom(Level), is_map(Fields) ->
    Entry = #structured_log{
        log_id = cb_correlation:generate_id(),
        level = atom_to_binary(Level, utf8),
        event = normalize_text(maps:get(event, Fields, undefined), <<"unknown">>),
        correlation_id = normalize_optional_text(maps:get(correlation_id, Fields, undefined)),
        method = normalize_optional_text(maps:get(method, Fields, undefined)),
        path = normalize_optional_text(maps:get(path, Fields, undefined)),
        status_code = normalize_optional_integer(maps:get(status_code, Fields, undefined)),
        duration = normalize_optional_integer(maps:get(duration, Fields, undefined)),
        metadata = maps:get(metadata, Fields, #{}),
        created_at = normalize_created_at(maps:get(created_at, Fields, undefined))
    },
    F = fun() -> mnesia:write(Entry) end,
    case mnesia:transaction(F) of
        {atomic, ok} -> ok;
        {aborted, Reason} -> {error, Reason}
    end.

-spec search(log_filters()) -> {ok, #{items => [map()], total => non_neg_integer(), limit => non_neg_integer(), offset => non_neg_integer()}} | {error, term()}.
search(Filters) when is_map(Filters) ->
    QueryFilters = normalize_search_filters(Filters),
    F = fun() ->
        mnesia:foldl(
            fun(Entry, Acc) ->
                case matches_filters(Entry, QueryFilters) of
                    true -> [entry_to_map(Entry) | Acc];
                    false -> Acc
                end
            end,
            [],
            ?TABLE
        )
    end,
    case mnesia:transaction(F) of
        {atomic, Items0} ->
            Items1 = lists:sort(fun sort_desc/2, Items0),
            Offset = maps:get(offset, QueryFilters),
            Limit = maps:get(limit, QueryFilters),
            Total = length(Items1),
            Items = take(Limit, drop(Offset, Items1)),
            {ok, #{items => Items, total => Total, limit => Limit, offset => Offset}};
        {aborted, Reason} ->
            {error, Reason}
    end.

-spec export_csv(log_filters()) -> {ok, binary()} | {error, term()}.
export_csv(Filters) when is_map(Filters) ->
    ExportFilters = case maps:is_key(limit, Filters) of
        true -> Filters;
        false -> Filters#{limit => ?DEFAULT_EXPORT_LIMIT, offset => 0}
    end,
    case search(ExportFilters) of
        {ok, #{items := Items}} ->
            Header = <<"log_id,level,event,correlation_id,method,path,status_code,duration,created_at,metadata\n">>,
            Rows = [csv_row(Item) || Item <- Items],
            {ok, iolist_to_binary([Header, Rows])};
        Error ->
            Error
    end.

-spec get_retention_policy() -> {ok, #{resource => binary(), retention_days => non_neg_integer(), source => binary()}} | {error, term()}.
get_retention_policy() ->
    F = fun() ->
        case mnesia:read({?RETENTION_TABLE, ?RETENTION_RESOURCE}) of
            [{audit_retention_policy, ?RETENTION_RESOURCE, Days, _CreatedAt, _UpdatedAt}] ->
                #{resource => <<"structured_log">>, retention_days => Days, source => <<"configured">>};
            [] ->
                #{resource => <<"structured_log">>, retention_days => ?DEFAULT_RETENTION_DAYS, source => <<"default">>}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Policy} -> {ok, Policy};
        {aborted, Reason} -> {error, Reason}
    end.

-spec set_retention_policy(non_neg_integer()) -> ok | {error, term()}.
set_retention_policy(Days) when is_integer(Days), Days >= 0 ->
    F = fun() ->
        Now = erlang:system_time(millisecond),
        mnesia:write({?RETENTION_TABLE, ?RETENTION_RESOURCE, Days, Now, Now})
    end,
    case mnesia:transaction(F) of
        {atomic, ok} -> ok;
        {aborted, Reason} -> {error, Reason}
    end.

-spec apply_retention() -> {ok, #{deleted => non_neg_integer(), retention_days => non_neg_integer()}} | {error, term()}.
apply_retention() ->
    case get_retention_policy_days() of
        {ok, 0} ->
            {ok, #{deleted => 0, retention_days => 0}};
        {ok, Days} ->
            Threshold = erlang:system_time(millisecond) - Days * 86400000,
            F = fun() ->
                OldIds = mnesia:foldl(
                    fun(#structured_log{log_id = LogId, created_at = CreatedAt}, Acc) when CreatedAt < Threshold ->
                            [LogId | Acc];
                       (_Entry, Acc) ->
                            Acc
                    end,
                    [],
                    ?TABLE
                ),
                lists:foreach(fun(LogId) -> mnesia:delete({?TABLE, LogId}) end, OldIds),
                length(OldIds)
            end,
            case mnesia:transaction(F) of
                {atomic, Count} -> {ok, #{deleted => Count, retention_days => Days}};
                {aborted, Reason} -> {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

-spec entry_to_map(#structured_log{}) -> map().
entry_to_map(#structured_log{} = Entry) ->
    Base = #{
        log_id => Entry#structured_log.log_id,
        level => Entry#structured_log.level,
        event => Entry#structured_log.event,
        created_at => Entry#structured_log.created_at,
        metadata => Entry#structured_log.metadata
    },
    maybe_put(correlation_id, Entry#structured_log.correlation_id,
        maybe_put(method, Entry#structured_log.method,
            maybe_put(path, Entry#structured_log.path,
                maybe_put(status_code, Entry#structured_log.status_code,
                    maybe_put(duration, Entry#structured_log.duration, Base))))).

normalize_search_filters(Filters) ->
    # {
        correlation_id => normalize_filter_binary(maps:get(correlation_id, Filters, undefined)),
        event => normalize_filter_binary(maps:get(event, Filters, undefined)),
        level => normalize_filter_binary(maps:get(level, Filters, undefined)),
        method => normalize_filter_binary(maps:get(method, Filters, undefined)),
        path => normalize_filter_binary(maps:get(path, Filters, undefined)),
        q => normalize_filter_binary(maps:get(q, Filters, undefined)),
        from => normalize_optional_integer(maps:get(from, Filters, undefined)),
        to => normalize_optional_integer(maps:get(to, Filters, undefined)),
        limit => normalize_limit(maps:get(limit, Filters, ?DEFAULT_LIMIT), ?DEFAULT_LIMIT),
        offset => normalize_limit(maps:get(offset, Filters, 0), 0)
    }.

matches_filters(#structured_log{} = Entry, Filters) ->
    matches_exact(Entry#structured_log.correlation_id, maps:get(correlation_id, Filters)) andalso
    matches_exact(Entry#structured_log.event, maps:get(event, Filters)) andalso
    matches_exact(Entry#structured_log.level, maps:get(level, Filters)) andalso
    matches_exact(Entry#structured_log.method, maps:get(method, Filters)) andalso
    matches_exact(Entry#structured_log.path, maps:get(path, Filters)) andalso
    matches_range(Entry#structured_log.created_at, maps:get(from, Filters), maps:get(to, Filters)) andalso
    matches_query(Entry, maps:get(q, Filters)).

matches_exact(_Value, undefined) ->
    true;
matches_exact(Value, Filter) ->
    Value =:= Filter.

matches_range(Value, undefined, undefined) when is_integer(Value) ->
    true;
matches_range(Value, From, undefined) when is_integer(Value), is_integer(From) ->
    Value >= From;
matches_range(Value, undefined, To) when is_integer(Value), is_integer(To) ->
    Value =< To;
matches_range(Value, From, To) when is_integer(Value), is_integer(From), is_integer(To) ->
    Value >= From andalso Value =< To.

matches_query(_Entry, undefined) ->
    true;
matches_query(#structured_log{} = Entry, Query) ->
    Corpus = iolist_to_binary([
        normalize_text(Entry#structured_log.event, <<>>), <<" ">>,
        normalize_text(Entry#structured_log.correlation_id, <<>>), <<" ">>,
        normalize_text(Entry#structured_log.method, <<>>), <<" ">>,
        normalize_text(Entry#structured_log.path, <<>>), <<" ">>,
        metadata_to_binary(Entry#structured_log.metadata)
    ]),
    binary:match(lower_binary(Corpus), lower_binary(Query)) =/= nomatch.

sort_desc(#{created_at := Left, log_id := LeftId}, #{created_at := Right, log_id := RightId}) when Left =:= Right ->
    LeftId >= RightId;
sort_desc(#{created_at := Left}, #{created_at := Right}) ->
    Left >= Right.

drop(0, Items) ->
    Items;
drop(N, [_ | Rest]) when N > 0 ->
    drop(N - 1, Rest);
drop(_, []) ->
    [].

take(N, _Items) when N =< 0 ->
    [];
take(_N, []) ->
    [];
take(N, [Item | Rest]) ->
    [Item | take(N - 1, Rest)].

csv_row(Item) ->
    Metadata = maps:get(metadata, Item, #{}),
    [
        csv_field(maps:get(log_id, Item)), <<",">>,
        csv_field(maps:get(level, Item)), <<",">>,
        csv_field(maps:get(event, Item)), <<",">>,
        csv_field(maps:get(correlation_id, Item, <<>>)), <<",">>,
        csv_field(maps:get(method, Item, <<>>)), <<",">>,
        csv_field(maps:get(path, Item, <<>>)), <<",">>,
        csv_field(maps:get(status_code, Item, <<>>)), <<",">>,
        csv_field(maps:get(duration, Item, <<>>)), <<",">>,
        csv_field(maps:get(created_at, Item)), <<",">>,
        csv_field(metadata_to_binary(Metadata)), <<"\n">>
    ].

csv_field(undefined) ->
    <<>>;
csv_field(Value) when is_integer(Value) ->
    integer_to_binary(Value);
csv_field(Value) when is_atom(Value) ->
    csv_field(atom_to_binary(Value, utf8));
csv_field(Value) when is_binary(Value) ->
    Escaped = binary:replace(Value, <<"\"">>, <<"\"\"">>, [global]),
    <<"\"", Escaped/binary, "\"">>;
csv_field(Value) ->
    csv_field(iolist_to_binary(io_lib:format("~p", [Value]))).

maybe_put(_Key, undefined, Map) ->
    Map;
maybe_put(Key, Value, Map) ->
    Map#{Key => Value}.

normalize_text(undefined, Default) ->
    Default;
normalize_text(Value, _Default) when is_binary(Value) ->
    Value;
normalize_text(Value, _Default) when is_atom(Value) ->
    atom_to_binary(Value, utf8);
normalize_text(Value, _Default) ->
    iolist_to_binary(io_lib:format("~p", [Value])).

normalize_optional_text(undefined) ->
    undefined;
normalize_optional_text(Value) ->
    normalize_text(Value, undefined).

normalize_filter_binary(undefined) ->
    undefined;
normalize_filter_binary(Value) when is_binary(Value), byte_size(Value) =:= 0 ->
    undefined;
normalize_filter_binary(Value) ->
    normalize_text(Value, undefined).

normalize_optional_integer(undefined) ->
    undefined;
normalize_optional_integer(Value) when is_integer(Value), Value >= 0 ->
    Value;
normalize_optional_integer(_Value) ->
    undefined.

normalize_created_at(Value) when is_integer(Value), Value >= 0 ->
    Value;
normalize_created_at(_Value) ->
    erlang:system_time(millisecond).

normalize_limit(Value, _Default) when is_integer(Value), Value >= 0 ->
    Value;
normalize_limit(_Value, Default) ->
    Default.

metadata_to_binary(Metadata) when is_map(Metadata) ->
    iolist_to_binary(io_lib:format("~p", [Metadata]));
metadata_to_binary(Value) when is_binary(Value) ->
    Value;
metadata_to_binary(Value) ->
    iolist_to_binary(io_lib:format("~p", [Value])).

lower_binary(Value) when is_binary(Value) ->
    unicode:characters_to_binary(string:lowercase(binary_to_list(Value))).

get_retention_policy_days() ->
    case get_retention_policy() of
        {ok, #{retention_days := Days}} -> {ok, Days};
        Error -> Error
    end.