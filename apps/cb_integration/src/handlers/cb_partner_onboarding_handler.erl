%% @doc HTTP handler for partner onboarding workflow.
%%
%% Routes:
%%   GET    /api/v1/marketplace/partners                — list all applications
%%   POST   /api/v1/marketplace/partners                — submit a new application
%%   GET    /api/v1/marketplace/partners/:id            — get application by ID
%%   POST   /api/v1/marketplace/partners/:id/approve    — approve application
%%   POST   /api/v1/marketplace/partners/:id/reject     — reject application
%%   GET    /api/v1/marketplace/partners/:id/compatibility — check compatibility
-module(cb_partner_onboarding_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

init(Req, State) ->
    Method = cowboy_req:method(Req),
    AppId  = cowboy_req:binding(application_id, Req),
    Action = cowboy_req:binding(action, Req),
    handle(Method, AppId, Action, Req, State).

%% List all
handle(<<"GET">>, undefined, undefined, Req, State) ->
    Apps = cb_partner_onboarding:list_applications(),
    Req2 = cowboy_req:reply(200, headers(),
               jsone:encode(#{applications => [app_to_map(A) || A <- Apps]}), Req),
    {ok, Req2, State};

%% Submit application
handle(<<"POST">>, undefined, undefined, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{name := Name, contact_email := Email} = P, _} ->
            Attrs = #{
                name                 => Name,
                contact_email        => Email,
                requested_connectors => maps:get(requested_connectors, P, [])
            },
            case cb_partner_onboarding:submit_application(Attrs) of
                {ok, App} ->
                    Req3 = cowboy_req:reply(201, headers(),
                               jsone:encode(app_to_map(App)), Req2),
                    {ok, Req3, State};
                {error, Reason} ->
                    error_reply(500, Reason, Req2, State)
            end;
        _ ->
            error_reply(400, <<"Missing required fields: name, contact_email">>, Req2, State)
    end;

%% Get by ID
handle(<<"GET">>, AppId, undefined, Req, State) ->
    case cb_partner_onboarding:get_application(AppId) of
        {ok, App} ->
            Req2 = cowboy_req:reply(200, headers(), jsone:encode(app_to_map(App)), Req),
            {ok, Req2, State};
        {error, not_found} ->
            error_reply(404, <<"not_found">>, Req, State)
    end;

%% Compatibility check
handle(<<"GET">>, AppId, <<"compatibility">>, Req, State) ->
    case cb_partner_onboarding:get_application(AppId) of
        {ok, #partner_application{requested_connectors = ConnIds}} ->
            Result = cb_partner_onboarding:check_compatibility(ConnIds),
            Body = case Result of
                ok ->
                    #{compatible => true, issues => []};
                {error, {incompatible_connectors, Ids}} ->
                    #{compatible => false, issues => Ids}
            end,
            Req2 = cowboy_req:reply(200, headers(), jsone:encode(Body), Req),
            {ok, Req2, State};
        {error, not_found} ->
            error_reply(404, <<"not_found">>, Req, State)
    end;

%% Approve
handle(<<"POST">>, AppId, <<"approve">>, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    ReviewedBy = case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{reviewed_by := Id}, _} -> Id;
        _ -> <<"system">>
    end,
    case cb_partner_onboarding:approve(AppId, ReviewedBy) of
        {ok, App} ->
            Req3 = cowboy_req:reply(200, headers(), jsone:encode(app_to_map(App)), Req2),
            {ok, Req3, State};
        {error, not_found} ->
            error_reply(404, <<"not_found">>, Req2, State);
        {error, {compatibility_check_failed, {incompatible_connectors, Ids}}} ->
            Msg = iolist_to_binary(io_lib:format("Incompatible connectors: ~p", [Ids])),
            error_reply(422, Msg, Req2, State);
        {error, {invalid_transition, From, _To}} ->
            Msg = iolist_to_binary(io_lib:format("Application is already ~s", [From])),
            error_reply(422, Msg, Req2, State);
        {error, Reason} ->
            error_reply(500, Reason, Req2, State)
    end;

%% Reject
handle(<<"POST">>, AppId, <<"reject">>, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    {ReviewedBy, Reason} = case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, P, _} ->
            {maps:get(reviewed_by, P, <<"system">>),
             maps:get(reason, P, <<"No reason provided">>)};
        _ ->
            {<<"system">>, <<"No reason provided">>}
    end,
    case cb_partner_onboarding:reject(AppId, ReviewedBy, Reason) of
        {ok, App} ->
            Req3 = cowboy_req:reply(200, headers(), jsone:encode(app_to_map(App)), Req2),
            {ok, Req3, State};
        {error, not_found} ->
            error_reply(404, <<"not_found">>, Req2, State);
        {error, {invalid_transition, From, _To}} ->
            Msg = iolist_to_binary(io_lib:format("Application is already ~s", [From])),
            error_reply(422, Msg, Req2, State);
        {error, RejectReason} ->
            error_reply(500, RejectReason, Req2, State)
    end;

handle(_, _, _, Req, State) ->
    Req2 = cowboy_req:reply(405, headers(), <<>>, Req),
    {ok, Req2, State}.

app_to_map(#partner_application{
    application_id       = Id,
    partner_id           = PartnerId,
    name                 = Name,
    contact_email        = Email,
    requested_connectors = Connectors,
    status               = Status,
    reviewed_by          = ReviewedBy,
    reviewed_at          = ReviewedAt,
    rejection_reason     = Rejection,
    created_at           = CreAt,
    updated_at           = UpdAt
}) ->
    #{
        application_id       => Id,
        partner_id           => PartnerId,
        name                 => Name,
        contact_email        => Email,
        requested_connectors => Connectors,
        status               => Status,
        reviewed_by          => ReviewedBy,
        reviewed_at          => ReviewedAt,
        rejection_reason     => Rejection,
        created_at           => CreAt,
        updated_at           => UpdAt
    }.

error_reply(Code, Reason, Req, State) ->
    Msg = if is_binary(Reason) -> Reason; true -> iolist_to_binary(io_lib:format("~p", [Reason])) end,
    Req2 = cowboy_req:reply(Code, headers(), jsone:encode(#{error => Msg}), Req),
    {ok, Req2, State}.

headers() ->
    maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()).
