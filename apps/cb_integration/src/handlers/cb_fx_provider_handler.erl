%% @doc HTTP handler for external FX provider management (P1-S3, TASK-034).
%%
%% Routes:
%%   GET    /api/v1/fx/providers                    — list providers
%%   POST   /api/v1/fx/providers                    — register provider
%%   GET    /api/v1/fx/providers/:provider_id        — get provider
%%   POST   /api/v1/fx/providers/:provider_id/enable  — enable provider
%%   POST   /api/v1/fx/providers/:provider_id/disable — disable provider
%%   POST   /api/v1/fx/providers/:provider_id/set-primary — promote to priority 1
%%   POST   /api/v1/fx/refresh                       — refresh all provider rates
%%   GET    /api/v1/fx/rate/:from/:to                — fetch best rate (fallback chain)
-module(cb_fx_provider_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

init(Req, State) ->
    Method     = cowboy_req:method(Req),
    ProviderId = cowboy_req:binding(provider_id, Req),
    Action     = cowboy_req:binding(action, Req),
    From       = cowboy_req:binding(from, Req),
    To         = cowboy_req:binding(to, Req),
    handle(Method, ProviderId, Action, From, To, Req, State).

%% List providers
handle(<<"GET">>, undefined, undefined, undefined, undefined, Req, State) ->
    Providers = cb_fx_provider:list_providers(),
    Body = jsone:encode(#{providers => [provider_to_map(P) || P <- Providers]}),
    Req2 = cowboy_req:reply(200, headers(), Body, Req),
    {ok, Req2, State};

%% Register provider
handle(<<"POST">>, undefined, undefined, undefined, undefined, Req, State) ->
    {ok, RawBody, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(RawBody, [{keys, atom}]) of
        {ok, #{name := Name, type := TypeBin} = P, _} ->
            Type   = binary_to_existing_atom(TypeBin, utf8),
            Config = maps:get(config, P, #{}),
            case cb_fx_provider:register_provider(Name, Type, Config) of
                {ok, Id} ->
                    Req3 = cowboy_req:reply(201, headers(),
                               jsone:encode(#{provider_id => Id}), Req2),
                    {ok, Req3, State};
                {error, already_registered} ->
                    error_reply(409, <<"already_registered">>, Req2, State);
                {error, Reason} ->
                    error_reply(500, Reason, Req2, State)
            end;
        _ ->
            error_reply(400, <<"Missing required fields: name, type">>, Req2, State)
    end;

%% Refresh all providers
handle(<<"POST">>, <<"refresh">>, undefined, undefined, undefined, Req, State) ->
    {ok, Count} = cb_fx_provider:refresh_all(),
    Req2 = cowboy_req:reply(200, headers(),
               jsone:encode(#{refreshed => Count}), Req),
    {ok, Req2, State};

%% Fetch best rate (fallback chain)
handle(<<"GET">>, undefined, undefined, From, To, Req, State) when From =/= undefined, To =/= undefined ->
    FromAtom = binary_to_existing_atom(From, utf8),
    ToAtom   = binary_to_existing_atom(To, utf8),
    Providers = [P#fx_provider.provider_id
                 || P <- cb_fx_provider:list_providers(),
                    P#fx_provider.status =:= active],
    case cb_fx_provider:fetch_with_fallback(Providers, FromAtom, ToAtom) of
        {ok, Rate} ->
            Req2 = cowboy_req:reply(200, headers(),
                       jsone:encode(#{from => From, to => To,
                                      rate_millionths => Rate}), Req),
            {ok, Req2, State};
        {error, no_provider_available} ->
            error_reply(503, <<"no_provider_available">>, Req, State);
        {error, same_currency} ->
            error_reply(400, <<"same_currency">>, Req, State)
    end;

%% Get provider
handle(<<"GET">>, ProviderId, undefined, _, _, Req, State) when ProviderId =/= undefined ->
    case cb_fx_provider:get_provider(ProviderId) of
        {ok, P} ->
            Req2 = cowboy_req:reply(200, headers(),
                       jsone:encode(provider_to_map(P)), Req),
            {ok, Req2, State};
        {error, not_found} ->
            error_reply(404, <<"not_found">>, Req, State)
    end;

%% Enable / disable / set-primary
handle(<<"POST">>, ProviderId, Action, _, _, Req, State) when ProviderId =/= undefined ->
    Result = case Action of
        <<"enable">>      -> cb_fx_provider:set_provider_status(ProviderId, active);
        <<"disable">>     -> cb_fx_provider:set_provider_status(ProviderId, disabled);
        <<"set-primary">> -> cb_fx_provider:set_primary(ProviderId);
        _                 -> {error, unknown_action}
    end,
    case Result of
        ok ->
            Req2 = cowboy_req:reply(200, headers(), jsone:encode(#{status => <<"ok">>}), Req),
            {ok, Req2, State};
        {error, not_found} ->
            error_reply(404, <<"not_found">>, Req, State);
        {error, unknown_action} ->
            error_reply(400, <<"unknown_action">>, Req, State);
        {error, Reason} ->
            error_reply(500, Reason, Req, State)
    end;

handle(_Method, _ProviderId, _Action, _From, _To, Req, State) ->
    error_reply(405, <<"method_not_allowed">>, Req, State).

%%--------------------------------------------------------------------
%% Helpers
%%--------------------------------------------------------------------

provider_to_map(#fx_provider{} = P) ->
    #{
        provider_id => P#fx_provider.provider_id,
        name        => P#fx_provider.name,
        type        => P#fx_provider.type,
        status      => P#fx_provider.status,
        priority    => P#fx_provider.priority,
        last_sync   => P#fx_provider.last_sync,
        created_at  => P#fx_provider.created_at
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
