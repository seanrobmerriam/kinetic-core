%% @doc Locale-Aware Communication Templates and Jurisdiction Flags (P1-S3, TASK-037).
%%
%% Provides a template registry for outbound communications (email, SMS, in-app)
%% with per-locale variants and jurisdiction-specific compliance flags.
%%
%% == Template Lifecycle ==
%%
%% ```
%% register_template/3     → store a template for a given event_type + locale
%% render_template/3       → look up template, substitute variables, return text
%% get_template/2          → read raw template record
%% list_templates/0        → all registered templates
%% list_templates_by_type/1 → filter by event_type
%% ```
%%
%% == Jurisdiction Flags ==
%%
%% Each locale can have jurisdiction-specific flags (e.g., GDPR, CCPA,
%% MAS Notice 655) that must be appended to certain communication types.
%%
%% ```
%% jurisdiction_flags/1    → return active compliance flags for a locale
%% render_with_flags/3     → render template and append mandatory flag text
%% ```
%%
%% == Variable Substitution ==
%%
%% Templates use `{{variable_name}}' placeholders. The `render_template/3'
%% function performs a single-pass substitution from the supplied Vars map.
%%
%% Example template body:
%%   <<"Dear {{party_name}}, your transfer of {{amount}} was {{status}}.">>
%%
%% Unresolved variables are left as-is.
-module(cb_locale_templates).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    %% Template management
    register_template/3,
    get_template/2,
    update_template/3,
    list_templates/0,
    list_templates_by_type/1,

    %% Rendering
    render_template/3,
    render_with_flags/3,

    %% Jurisdiction flags
    jurisdiction_flags/1,
    set_jurisdiction_flag/3,
    clear_jurisdiction_flag/2
]).

%%--------------------------------------------------------------------
%% Template Management
%%--------------------------------------------------------------------

%% @doc Register a new communication template.
%%
%% `EventType' — binary key such as <<"payment_completed">> or <<"kyc_approved">>.
%% `Locale'    — IETF locale, e.g. <<"en-US">>.
%% `Body'      — template string with `{{variable}}' placeholders.
-spec register_template(binary(), binary(), binary()) ->
    {ok, binary()} | {error, already_registered | atom()}.
register_template(EventType, Locale, Body)
        when is_binary(EventType), is_binary(Locale), is_binary(Body) ->
    case get_template(EventType, Locale) of
        {ok, _} -> {error, already_registered};
        {error, not_found} ->
            TemplateId = uuid:uuid_to_string(uuid:get_v4(), binary_standard),
            Now = erlang:system_time(millisecond),
            Row = #locale_template{
                template_id  = TemplateId,
                event_type   = EventType,
                locale       = Locale,
                body         = Body,
                created_at   = Now,
                updated_at   = Now
            },
            {atomic, ok} = mnesia:transaction(fun() -> mnesia:write(Row) end),
            {ok, TemplateId}
    end.

%% @doc Retrieve a template by event_type + locale.
-spec get_template(binary(), binary()) ->
    {ok, #locale_template{}} | {error, not_found}.
get_template(EventType, Locale) ->
    Key = {EventType, Locale},
    case mnesia:dirty_read(locale_template_by_key, Key) of
        [T] -> {ok, T};
        []  ->
            %% Secondary lookup: scan by event_type index
            All = mnesia:dirty_index_read(locale_template, EventType, event_type),
            case [T || T <- All, T#locale_template.locale =:= Locale] of
                [T | _] -> {ok, T};
                []      -> {error, not_found}
            end
    end.

%% @doc Update an existing template's body text.
-spec update_template(binary(), binary(), binary()) ->
    ok | {error, not_found | atom()}.
update_template(EventType, Locale, NewBody) ->
    F = fun() ->
        All = mnesia:index_read(locale_template, EventType, event_type),
        case [T || T <- All, T#locale_template.locale =:= Locale] of
            [] -> {error, not_found};
            [T | _] ->
                Now = erlang:system_time(millisecond),
                mnesia:write(T#locale_template{body = NewBody, updated_at = Now})
        end
    end,
    case mnesia:transaction(F) of
        {atomic, ok}                 -> ok;
        {atomic, {error, not_found}} -> {error, not_found};
        {aborted, Reason}            -> {error, Reason}
    end.

%% @doc List all registered templates.
-spec list_templates() -> [#locale_template{}].
list_templates() ->
    {atomic, All} = mnesia:transaction(fun() ->
        mnesia:foldl(fun(T, Acc) -> [T | Acc] end, [], locale_template)
    end),
    lists:sort(fun(A, B) ->
        {A#locale_template.event_type, A#locale_template.locale} =<
        {B#locale_template.event_type, B#locale_template.locale}
    end, All).

%% @doc List templates for a given event type (all locales).
-spec list_templates_by_type(binary()) -> [#locale_template{}].
list_templates_by_type(EventType) ->
    mnesia:dirty_index_read(locale_template, EventType, event_type).

%%--------------------------------------------------------------------
%% Rendering
%%--------------------------------------------------------------------

%% @doc Render a template with variable substitution.
%%
%% `Vars' — map of `binary()' to `binary()' variable bindings.
%%
%% Returns {ok, RenderedBody} or falls back to the "en-US" template if
%% no template for the requested locale is registered.
-spec render_template(binary(), binary(), map()) ->
    {ok, binary()} | {error, not_found}.
render_template(EventType, Locale, Vars) ->
    Result = case get_template(EventType, Locale) of
        {ok, T}            -> {ok, T#locale_template.body};
        {error, not_found} ->
            case get_template(EventType, <<"en-US">>) of
                {ok, T}    -> {ok, T#locale_template.body};
                {error, _} -> {error, not_found}
            end
    end,
    case Result of
        {error, _} = Err -> Err;
        {ok, Body}       -> {ok, substitute(Body, Vars)}
    end.

%% @doc Render a template and append mandatory jurisdiction flag text.
-spec render_with_flags(binary(), binary(), map()) ->
    {ok, binary()} | {error, not_found}.
render_with_flags(EventType, Locale, Vars) ->
    case render_template(EventType, Locale, Vars) of
        {error, _} = Err -> Err;
        {ok, Body} ->
            Flags = jurisdiction_flags(Locale),
            FlagText = build_flag_text(Flags),
            if
                FlagText =:= <<>> -> {ok, Body};
                true              -> {ok, <<Body/binary, "\n\n", FlagText/binary>>}
            end
    end.

%%--------------------------------------------------------------------
%% Jurisdiction Flags
%%--------------------------------------------------------------------

%% @doc Return the active compliance flag records for a locale.
-spec jurisdiction_flags(binary()) -> [#jurisdiction_flag{}].
jurisdiction_flags(Locale) ->
    All = mnesia:dirty_index_read(jurisdiction_flag, Locale, locale),
    [F || F <- All, F#jurisdiction_flag.active =:= true].

%% @doc Upsert a jurisdiction compliance flag for a locale.
%%
%% `FlagType' — atom such as `gdpr' | `ccpa' | `mas_notice_655'.
%% `Text'      — disclosure text appended to communications.
-spec set_jurisdiction_flag(binary(), atom(), binary()) ->
    ok | {error, atom()}.
set_jurisdiction_flag(Locale, FlagType, Text) ->
    FlagId = <<Locale/binary, "_", (atom_to_binary(FlagType, utf8))/binary>>,
    Now    = erlang:system_time(millisecond),
    Row    = #jurisdiction_flag{
        flag_id    = FlagId,
        locale     = Locale,
        flag_type  = FlagType,
        text       = Text,
        active     = true,
        updated_at = Now
    },
    case mnesia:transaction(fun() -> mnesia:write(Row) end) of
        {atomic, ok}      -> ok;
        {aborted, Reason} -> {error, Reason}
    end.

%% @doc Deactivate a jurisdiction flag so it is no longer appended.
-spec clear_jurisdiction_flag(binary(), atom()) ->
    ok | {error, not_found | atom()}.
clear_jurisdiction_flag(Locale, FlagType) ->
    FlagId = <<Locale/binary, "_", (atom_to_binary(FlagType, utf8))/binary>>,
    F = fun() ->
        case mnesia:read(jurisdiction_flag, FlagId) of
            []  -> {error, not_found};
            [R] -> mnesia:write(R#jurisdiction_flag{active = false})
        end
    end,
    case mnesia:transaction(F) of
        {atomic, ok}                 -> ok;
        {atomic, {error, not_found}} -> {error, not_found};
        {aborted, Reason}            -> {error, Reason}
    end.

%%--------------------------------------------------------------------
%% Internal helpers
%%--------------------------------------------------------------------

%% Single-pass `{{key}}' substitution over a binary.
substitute(Body, Vars) ->
    maps:fold(fun(K, V, Acc) ->
        Placeholder = <<"{{", K/binary, "}}">>,
        binary:replace(Acc, Placeholder, V, [global])
    end, Body, Vars).

build_flag_text([]) -> <<"">>;
build_flag_text(Flags) ->
    Parts = [F#jurisdiction_flag.text || F <- Flags],
    join_binaries(Parts, <<"\n">>).

join_binaries([], _Sep)     -> <<"">>;
join_binaries([H], _Sep)    -> H;
join_binaries([H | T], Sep) -> <<H/binary, Sep/binary, (join_binaries(T, Sep))/binary>>.
