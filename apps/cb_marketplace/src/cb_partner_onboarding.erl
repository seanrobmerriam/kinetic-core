%% @doc Partner onboarding workflow and compatibility checks.
%%
%% Partners submit applications requesting access to marketplace connectors.
%% Operations staff approve or reject applications. Before approval, a
%% compatibility check validates that all requested connectors are registered
%% and in `enabled' status.
%%
%% Workflow: pending → approved | rejected (terminal states)
-module(cb_partner_onboarding).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    submit_application/1,
    approve/2,
    reject/3,
    get_application/1,
    list_applications/0,
    list_pending/0,
    check_compatibility/1
]).

%% ---------------------------------------------------------------------------
%% Public API
%% ---------------------------------------------------------------------------

-spec submit_application(map()) -> {ok, #partner_application{}} | {error, term()}.
submit_application(Attrs) ->
    ApplicationId = uuid:get_v4_urandom(),
    PartnerId     = uuid:get_v4_urandom(),
    Now           = erlang:system_time(millisecond),
    App = #partner_application{
        application_id       = ApplicationId,
        partner_id           = PartnerId,
        name                 = maps:get(name, Attrs),
        contact_email        = maps:get(contact_email, Attrs),
        requested_connectors = maps:get(requested_connectors, Attrs, []),
        status               = pending,
        reviewed_by          = undefined,
        reviewed_at          = undefined,
        rejection_reason     = undefined,
        created_at           = Now,
        updated_at           = Now
    },
    case mnesia:transaction(fun() -> mnesia:write(App) end) of
        {atomic, ok} -> {ok, App};
        {aborted, Reason} -> {error, Reason}
    end.

-spec approve(uuid(), uuid()) -> {ok, #partner_application{}} | {error, term()}.
approve(ApplicationId, ReviewedBy) ->
    F = fun() ->
        case mnesia:read(partner_application, ApplicationId, write) of
            [] ->
                {error, not_found};
            [#partner_application{status = pending} = App] ->
                case check_compatibility(App#partner_application.requested_connectors) of
                    ok ->
                        Now = erlang:system_time(millisecond),
                        Updated = App#partner_application{
                            status      = approved,
                            reviewed_by = ReviewedBy,
                            reviewed_at = Now,
                            updated_at  = Now
                        },
                        mnesia:write(Updated),
                        {ok, Updated};
                    {error, Reason} ->
                        {error, {compatibility_check_failed, Reason}}
                end;
            [#partner_application{status = Status}] ->
                {error, {invalid_transition, Status, approved}}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, Reason} -> {error, Reason}
    end.

-spec reject(uuid(), uuid(), binary()) -> {ok, #partner_application{}} | {error, term()}.
reject(ApplicationId, ReviewedBy, Reason) ->
    F = fun() ->
        case mnesia:read(partner_application, ApplicationId, write) of
            [] ->
                {error, not_found};
            [#partner_application{status = pending} = App] ->
                Now = erlang:system_time(millisecond),
                Updated = App#partner_application{
                    status           = rejected,
                    reviewed_by      = ReviewedBy,
                    reviewed_at      = Now,
                    rejection_reason = Reason,
                    updated_at       = Now
                },
                mnesia:write(Updated),
                {ok, Updated};
            [#partner_application{status = Status}] ->
                {error, {invalid_transition, Status, rejected}}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, Reason} -> {error, Reason}
    end.

-spec get_application(uuid()) -> {ok, #partner_application{}} | {error, not_found}.
get_application(ApplicationId) ->
    case mnesia:dirty_read(partner_application, ApplicationId) of
        [App] -> {ok, App};
        []    -> {error, not_found}
    end.

-spec list_applications() -> [#partner_application{}].
list_applications() ->
    mnesia:dirty_select(partner_application, [{'_', [], ['$_']}]).

-spec list_pending() -> [#partner_application{}].
list_pending() ->
    mnesia:dirty_index_read(partner_application, pending, #partner_application.status).

%% @doc Check that all requested connector IDs are registered and enabled.
-spec check_compatibility([uuid()]) -> ok | {error, {incompatible_connectors, [uuid()]}}.
check_compatibility(RequestedConnectors) ->
    Incompatible = lists:filter(fun(Id) -> not is_enabled(Id) end, RequestedConnectors),
    case Incompatible of
        [] -> ok;
        _  -> {error, {incompatible_connectors, Incompatible}}
    end.

%% ---------------------------------------------------------------------------
%% Internal
%% ---------------------------------------------------------------------------

-spec is_enabled(uuid()) -> boolean().
is_enabled(ConnectorId) ->
    case mnesia:dirty_read(connector_definition, ConnectorId) of
        [#connector_definition{status = enabled}] -> true;
        _ -> false
    end.
