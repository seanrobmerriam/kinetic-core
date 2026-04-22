%% @doc API Deprecation Registry
%%
%% Static registry of deprecated paths with sunset dates.
%% Consumed by `cb_deprecation_middleware' to inject HTTP warning headers
%% and by `cb_deprecation_handler' to expose the deprecation notice catalogue.
-module(cb_deprecation).

-export([is_deprecated/1, list_deprecated/0, entry_to_map/1]).

-type deprecation_entry() :: #{
    path        := binary(),
    sunset_date := binary(),
    successor   := binary() | undefined,
    description := binary()
}.

%% @doc Return all deprecated path entries.
-spec list_deprecated() -> [deprecation_entry()].
list_deprecated() ->
    [
        #{
            path        => <<"/api/v1/customers">>,
            sunset_date => <<"2025-12-31">>,
            successor   => <<"/api/v1/parties">>,
            description => <<"Use /api/v1/parties. The /customers alias will be removed.">>
        },
        #{
            path        => <<"/api/v1/accounts/legacy">>,
            sunset_date => <<"2025-09-30">>,
            successor   => <<"/api/v1/accounts">>,
            description => <<"Legacy account list endpoint. Use /api/v1/accounts instead.">>
        }
    ].

%% @doc Check whether a request path matches a deprecated entry.
%%
%% Returns `{true, Entry}' if deprecated, `false' otherwise.
-spec is_deprecated(binary()) -> {true, deprecation_entry()} | false.
is_deprecated(Path) when is_binary(Path) ->
    Entries = list_deprecated(),
    case lists:filter(fun(E) -> maps:get(path, E) =:= Path end, Entries) of
        [Entry | _] -> {true, Entry};
        []          -> false
    end.

%% @doc Serialise an entry for JSON output.
-spec entry_to_map(deprecation_entry()) -> map().
entry_to_map(Entry) ->
    #{
        path        => maps:get(path, Entry),
        sunset_date => maps:get(sunset_date, Entry),
        successor   => maps:get(successor, Entry, null),
        description => maps:get(description, Entry)
    }.
