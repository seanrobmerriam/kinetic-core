%% @doc Optimistic Concurrency and Conflict-Resolution (TASK-067).
%%
%% Provides version tokens for any resource.  Callers acquire a token,
%% carry the version integer alongside their read, and present it back on
%% write via cas_update/3.  If the stored version differs from the expected
%% version the write is rejected with {conflict, CurrentVersion}.
%%
%% Conflict resolution strategies:
%%   last_write_wins — the incoming write always wins (unsafe; caller opt-in).
%%   reject           — the default; return {conflict, V} and let the caller retry.
-module(cb_concurrency).
-compile({parse_transform, ms_transform}).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    acquire_token/2,
    latest_version/1,
    cas_update/3,
    resolve_conflict/3,
    list_tokens/1
]).

-type resource_ref() :: {resource_type(), uuid()}.
-type resource_type() :: binary().
-type conflict_strategy() :: reject | last_write_wins.

-spec acquire_token(resource_type(), uuid()) -> {ok, non_neg_integer()}.
acquire_token(ResourceType, ResourceId) ->
    TokenId = token_key(ResourceType, ResourceId),
    Now = erlang:system_time(millisecond),
    {atomic, Version} = mnesia:transaction(fun() ->
        case mnesia:read(version_token, TokenId) of
            [] ->
                Record = #version_token{
                    token_id      = TokenId,
                    resource_type = ResourceType,
                    resource_id   = ResourceId,
                    version       = 0,
                    created_at    = Now,
                    updated_at    = Now
                },
                mnesia:write(Record),
                0;
            [T] ->
                T#version_token.version
        end
    end),
    {ok, Version}.

-spec latest_version(resource_ref()) -> {ok, non_neg_integer()} | {error, not_found}.
latest_version({ResourceType, ResourceId}) ->
    case mnesia:dirty_read(version_token, token_key(ResourceType, ResourceId)) of
        [T] -> {ok, T#version_token.version};
        []  -> {error, not_found}
    end.

%% @doc Compare-and-swap update.
%%
%% WriteFun is called only if the current stored version equals ExpectedVersion.
%% WriteFun receives the current version and must return ok or {error, Reason}.
%% On success the version token is incremented atomically.
-spec cas_update(resource_ref(), non_neg_integer(), fun((non_neg_integer()) -> ok | {error, term()}))
      -> ok | {conflict, non_neg_integer()} | {error, term()}.
cas_update({ResourceType, ResourceId}, ExpectedVersion, WriteFun) ->
    TokenId = token_key(ResourceType, ResourceId),
    Now     = erlang:system_time(millisecond),
    case mnesia:transaction(fun() ->
        CurrentVersion = case mnesia:read(version_token, TokenId) of
            []  -> 0;
            [T] -> T#version_token.version
        end,
        if CurrentVersion =/= ExpectedVersion ->
            {conflict, CurrentVersion};
        true ->
            case WriteFun(CurrentVersion) of
                ok ->
                    NewToken = #version_token{
                        token_id      = TokenId,
                        resource_type = ResourceType,
                        resource_id   = ResourceId,
                        version       = CurrentVersion + 1,
                        created_at    = Now,
                        updated_at    = Now
                    },
                    mnesia:write(NewToken),
                    ok;
                {error, _} = Err ->
                    mnesia:abort(Err)
            end
        end
    end) of
        {atomic, Result}  -> Result;
        {aborted, {error, Reason}} -> {error, Reason};
        {aborted, Reason} -> {error, Reason}
    end.

%% @doc Apply a named conflict resolution strategy.
%%
%% reject          — always returns {conflict, CurrentVersion}.
%% last_write_wins — forcibly increments the version and calls WriteFun.
-spec resolve_conflict(resource_ref(), conflict_strategy(), fun(() -> ok | {error, term()}))
      -> ok | {conflict, non_neg_integer()} | {error, term()}.
resolve_conflict(Ref, reject, _WriteFun) ->
    case latest_version(Ref) of
        {ok, V}            -> {conflict, V};
        {error, not_found} -> {conflict, 0}
    end;
resolve_conflict({ResourceType, ResourceId} = Ref, last_write_wins, WriteFun) ->
    case latest_version(Ref) of
        {ok, V} ->
            cas_update({ResourceType, ResourceId}, V, fun(_) -> WriteFun() end);
        {error, not_found} ->
            cas_update({ResourceType, ResourceId}, 0, fun(_) -> WriteFun() end)
    end.

-spec list_tokens(resource_type()) -> [#version_token{}].
list_tokens(ResourceType) ->
    MS = ets:fun2ms(fun(#version_token{resource_type = RT} = T)
                        when RT =:= ResourceType -> T end),
    {atomic, Tokens} = mnesia:transaction(fun() ->
        mnesia:select(version_token, MS)
    end),
    Tokens.

%%--------------------------------------------------------------------
%% Internal
%%--------------------------------------------------------------------

token_key(ResourceType, ResourceId) ->
    <<ResourceType/binary, ":", ResourceId/binary>>.
