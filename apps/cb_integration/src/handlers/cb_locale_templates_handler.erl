%% @doc HTTP handler for locale templates and jurisdiction flags (P1-S3, TASK-037).
%%
%% Routes:
%%   GET    /api/v1/locale/templates                              — list all templates
%%   POST   /api/v1/locale/templates                              — register template
%%   GET    /api/v1/locale/templates/:event_type/:locale          — get template
%%   PUT    /api/v1/locale/templates/:event_type/:locale          — update body
%%   POST   /api/v1/locale/templates/:event_type/:locale/render   — render with vars
%%   GET    /api/v1/locale/flags/:locale                          — list flags for locale
%%   POST   /api/v1/locale/flags/:locale                          — set/upsert flag
%%   DELETE /api/v1/locale/flags/:locale/:flag_type               — clear (deactivate) flag
-module(cb_locale_templates_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

init(Req, State) ->
    Method    = cowboy_req:method(Req),
    Segment1  = cowboy_req:binding(segment1, Req),    %% event_type OR locale (flag routes)
    Segment2  = cowboy_req:binding(segment2, Req),    %% locale OR flag_type
    Action    = cowboy_req:binding(action, Req),       %% "render" or undefined
    handle(Method, Segment1, Segment2, Action, Req, State).

%% List all templates
handle(<<"GET">>, undefined, undefined, undefined, Req, State) ->
    Templates = cb_locale_templates:list_templates(),
    Body = jsone:encode(#{templates => [template_to_map(T) || T <- Templates]}),
    Req2 = cowboy_req:reply(200, headers(), Body, Req),
    {ok, Req2, State};

%% Register template
handle(<<"POST">>, undefined, undefined, undefined, Req, State) ->
    {ok, RawBody, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(RawBody, [{keys, atom}]) of
        {ok, #{event_type := ET, locale := Locale, body := Body}, _} ->
            case cb_locale_templates:register_template(ET, Locale, Body) of
                {ok, TemplateId} ->
                    Req3 = cowboy_req:reply(201, headers(),
                               jsone:encode(#{template_id => TemplateId}), Req2),
                    {ok, Req3, State};
                {error, already_registered} ->
                    error_reply(409, <<"already_registered">>, Req2, State);
                {error, Reason} ->
                    error_reply(500, Reason, Req2, State)
            end;
        _ ->
            error_reply(400, <<"Missing required fields: event_type, locale, body">>, Req2, State)
    end;

%% Get template by event_type + locale
handle(<<"GET">>, ET, Locale, undefined, Req, State)
        when ET =/= undefined, Locale =/= undefined ->
    case cb_locale_templates:get_template(ET, Locale) of
        {ok, T} ->
            Req2 = cowboy_req:reply(200, headers(),
                       jsone:encode(template_to_map(T)), Req),
            {ok, Req2, State};
        {error, not_found} ->
            error_reply(404, <<"not_found">>, Req, State)
    end;

%% Update template body
handle(<<"PUT">>, ET, Locale, undefined, Req, State)
        when ET =/= undefined, Locale =/= undefined ->
    {ok, RawBody, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(RawBody, [{keys, atom}]) of
        {ok, #{body := NewBody}, _} ->
            case cb_locale_templates:update_template(ET, Locale, NewBody) of
                ok ->
                    Req3 = cowboy_req:reply(200, headers(),
                               jsone:encode(#{status => <<"ok">>}), Req2),
                    {ok, Req3, State};
                {error, not_found} ->
                    error_reply(404, <<"not_found">>, Req2, State);
                {error, Reason} ->
                    error_reply(500, Reason, Req2, State)
            end;
        _ ->
            error_reply(400, <<"Missing required field: body">>, Req2, State)
    end;

%% Render template
handle(<<"POST">>, ET, Locale, <<"render">>, Req, State)
        when ET =/= undefined, Locale =/= undefined ->
    {ok, RawBody, Req2} = cowboy_req:read_body(Req),
    Vars = case jsone:try_decode(RawBody, [{keys, binary}]) of
        {ok, M, _} when is_map(M) -> M;
        _                          -> #{}
    end,
    case cb_locale_templates:render_with_flags(ET, Locale, Vars) of
        {ok, Rendered} ->
            Req3 = cowboy_req:reply(200, headers(),
                       jsone:encode(#{rendered => Rendered}), Req2),
            {ok, Req3, State};
        {error, not_found} ->
            error_reply(404, <<"not_found">>, Req2, State)
    end;

%% List jurisdiction flags for a locale (flag routes use /flags prefix — Segment1 = locale)
handle(<<"GET">>, Locale, undefined, undefined, Req, State) when Locale =/= undefined ->
    Flags = cb_locale_templates:jurisdiction_flags(Locale),
    Body  = jsone:encode(#{flags => [flag_to_map(F) || F <- Flags]}),
    Req2  = cowboy_req:reply(200, headers(), Body, Req),
    {ok, Req2, State};

%% Upsert jurisdiction flag
handle(<<"POST">>, Locale, undefined, undefined, Req, State) when Locale =/= undefined ->
    {ok, RawBody, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(RawBody, [{keys, atom}]) of
        {ok, #{flag_type := FlagTypeBin, text := Text}, _} ->
            FlagType = binary_to_existing_atom(FlagTypeBin, utf8),
            case cb_locale_templates:set_jurisdiction_flag(Locale, FlagType, Text) of
                ok ->
                    Req3 = cowboy_req:reply(201, headers(),
                               jsone:encode(#{status => <<"ok">>}), Req2),
                    {ok, Req3, State};
                {error, Reason} ->
                    error_reply(500, Reason, Req2, State)
            end;
        _ ->
            error_reply(400, <<"Missing required fields: flag_type, text">>, Req2, State)
    end;

%% Clear jurisdiction flag
handle(<<"DELETE">>, Locale, FlagTypeBin, undefined, Req, State)
        when Locale =/= undefined, FlagTypeBin =/= undefined ->
    FlagType = binary_to_existing_atom(FlagTypeBin, utf8),
    case cb_locale_templates:clear_jurisdiction_flag(Locale, FlagType) of
        ok ->
            Req2 = cowboy_req:reply(204, headers(), <<>>, Req),
            {ok, Req2, State};
        {error, not_found} ->
            error_reply(404, <<"not_found">>, Req, State);
        {error, Reason} ->
            error_reply(500, Reason, Req, State)
    end;

handle(_Method, _S1, _S2, _Action, Req, State) ->
    error_reply(405, <<"method_not_allowed">>, Req, State).

%%--------------------------------------------------------------------
%% Serialization helpers
%%--------------------------------------------------------------------

template_to_map(#locale_template{} = T) ->
    #{
        template_id => T#locale_template.template_id,
        event_type  => T#locale_template.event_type,
        locale      => T#locale_template.locale,
        body        => T#locale_template.body,
        created_at  => T#locale_template.created_at,
        updated_at  => T#locale_template.updated_at
    }.

flag_to_map(#jurisdiction_flag{} = F) ->
    #{
        flag_id    => F#jurisdiction_flag.flag_id,
        locale     => F#jurisdiction_flag.locale,
        flag_type  => F#jurisdiction_flag.flag_type,
        text       => F#jurisdiction_flag.text,
        active     => F#jurisdiction_flag.active,
        updated_at => F#jurisdiction_flag.updated_at
    }.

headers() ->
    #{<<"content-type">> => <<"application/json">>}.

error_reply(Code, Reason, Req, State) ->
    Body = jsone:encode(#{error => to_binary(Reason)}),
    Req2 = cowboy_req:reply(Code, headers(), Body, Req),
    {ok, Req2, State}.

to_binary(R) when is_atom(R)   -> atom_to_binary(R, utf8);
to_binary(R) when is_binary(R) -> R;
to_binary(R)                   -> iolist_to_binary(io_lib:format("~p", [R])).
