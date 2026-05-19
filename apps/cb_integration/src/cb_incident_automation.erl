%% @doc Incident response automation with escalation policies and post-mortem templates.
-module(cb_incident_automation).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    list_incidents/1,
    sync_from_slo/0,
    acknowledge/2,
    resolve/3,
    templates/0
]).

-define(TABLE, incident_response).
-define(DEFAULT_LIMIT, 50).

-spec list_incidents(map()) -> {ok, #{items => [map()], total => non_neg_integer(), limit => non_neg_integer(), offset => non_neg_integer()}} | {error, term()}.
list_incidents(Filters) when is_map(Filters) ->
    Normalized = normalize_filters(Filters),
    F = fun() ->
        mnesia:foldl(
            fun(Rec, Acc) ->
                case matches_filters(Rec, Normalized) of
                    true -> [incident_to_map(Rec) | Acc];
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
            Offset = maps:get(offset, Normalized),
            Limit = maps:get(limit, Normalized),
            Total = length(Items1),
            Items = take(Limit, drop(Offset, Items1)),
            {ok, #{items => Items, total => Total, limit => Limit, offset => Offset}};
        {aborted, Reason} ->
            {error, Reason}
    end.

-spec sync_from_slo() -> {ok, #{created => non_neg_integer(), updated => non_neg_integer(), auto_resolved => non_neg_integer(), active_alerts => non_neg_integer(), generated_at_ms => non_neg_integer()}} | {error, term()}.
sync_from_slo() ->
    Snapshot = cb_slo_policies:evaluate(),
    Alerts = maps:get(alerts, Snapshot, []),
    FiringAlerts = [A || A <- Alerts, maps:get(state, A, monitoring) =:= firing],
    Now = erlang:system_time(millisecond),
    F = fun() ->
        Existing = mnesia:foldl(fun(Rec, Acc) -> [Rec | Acc] end, [], ?TABLE),
        ExistingByAlert = maps:from_list([
            {Rec#incident_response.source_alert_id, Rec}
            || Rec <- Existing
        ]),
        ActiveIds = [normalize_text(maps:get(alert_id, Alert, <<>>)) || Alert <- FiringAlerts],
        {Created, Updated} = lists:foldl(
            fun(Alert, {CAcc, UAcc}) ->
                AlertId = normalize_text(maps:get(alert_id, Alert, <<>>)),
                case maps:get(AlertId, ExistingByAlert, undefined) of
                    undefined ->
                        Rec = new_incident(Alert, Now),
                        ok = mnesia:write(Rec),
                        {CAcc + 1, UAcc};
                    ExistingRec ->
                        UpdatedRec = refresh_incident(ExistingRec, Alert, Now),
                        ok = mnesia:write(UpdatedRec),
                        {CAcc, UAcc + 1}
                end
            end,
            {0, 0},
            FiringAlerts
        ),
        AutoResolved = lists:foldl(
            fun(Rec, Acc) ->
                IsOpen = Rec#incident_response.status =/= <<"resolved">>,
                IsActive = lists:member(Rec#incident_response.source_alert_id, ActiveIds),
                case IsOpen andalso (not IsActive) of
                    true ->
                        ok = mnesia:write(auto_resolve_incident(Rec, Now)),
                        Acc + 1;
                    false ->
                        Acc
                end
            end,
            0,
            Existing
        ),
        #{
            created => Created,
            updated => Updated,
            auto_resolved => AutoResolved,
            active_alerts => length(FiringAlerts),
            generated_at_ms => Now
        }
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> {ok, Result};
        {aborted, Reason} -> {error, Reason}
    end.

-spec acknowledge(binary(), binary()) -> {ok, map()} | {error, term()}.
acknowledge(IncidentId, Owner) when is_binary(IncidentId), is_binary(Owner) ->
    mutate_incident(IncidentId,
        fun(Rec, Now) ->
            case Rec#incident_response.status of
                <<"resolved">> -> {error, already_resolved};
                _ ->
                    {ok, Rec#incident_response{
                        status = <<"acknowledged">>,
                        owner = Owner,
                        updated_at = Now
                    }}
            end
        end
    ).

-spec resolve(binary(), binary(), binary()) -> {ok, map()} | {error, term()}.
resolve(IncidentId, Resolver, Summary)
    when is_binary(IncidentId), is_binary(Resolver), is_binary(Summary) ->
    mutate_incident(IncidentId,
        fun(Rec, Now) ->
            Draft = build_postmortem_draft(Rec, Resolver, Summary, Now),
            {ok, Rec#incident_response{
                status = <<"resolved">>,
                summary = Summary,
                postmortem_draft = Draft,
                resolved_at = Now,
                resolved_by = Resolver,
                updated_at = Now
            }}
        end
    ).

-spec templates() -> [map()].
templates() ->
    [
        #{
            template_id => <<"p1-major-incident">>,
            severity => <<"critical">>,
            title => <<"P1 Major Incident Post-Mortem">>,
            sections => [
                <<"Customer Impact">>,
                <<"Timeline (UTC)">>,
                <<"Detection and Escalation">>,
                <<"Root Cause">>,
                <<"Immediate Mitigations">>,
                <<"Corrective Actions">>,
                <<"Follow-up Owners and Due Dates">>
            ]
        },
        #{
            template_id => <<"p2-degraded-service">>,
            severity => <<"warning">>,
            title => <<"P2 Degraded Service Post-Mortem">>,
            sections => [
                <<"Service Scope">>,
                <<"Timeline (UTC)">>,
                <<"Escalation Path Taken">>,
                <<"Contributing Factors">>,
                <<"Recovery Steps">>,
                <<"Preventive Changes">>
            ]
        },
        #{
            template_id => <<"p3-monitoring-only">>,
            severity => <<"info">>,
            title => <<"P3 Monitoring Event Review">>,
            sections => [
                <<"Observed Signal">>,
                <<"Validation Performed">>,
                <<"Disposition">>,
                <<"Follow-up">>
            ]
        }
    ].

mutate_incident(IncidentId, Mutator) ->
    F = fun() ->
        case mnesia:read({?TABLE, IncidentId}) of
            [Rec] ->
                Now = erlang:system_time(millisecond),
                case Mutator(Rec, Now) of
                    {ok, UpdatedRec} ->
                        ok = mnesia:write(UpdatedRec),
                        {ok, incident_to_map(UpdatedRec)};
                    {error, Reason} ->
                        {error, Reason}
                end;
            [] ->
                {error, not_found}
        end
    end,
    case mnesia:transaction(F) of
        {atomic, Result} -> Result;
        {aborted, Reason} -> {error, Reason}
    end.

new_incident(Alert, Now) ->
    AlertId = normalize_text(maps:get(alert_id, Alert, <<"unknown">>)),
    Severity = normalize_text(maps:get(severity, Alert, <<"warning">>)),
    Objective = normalize_text(maps:get(objective, Alert, <<"unknown">>)),
    #incident_response{
        incident_id = incident_id(AlertId),
        source_alert_id = AlertId,
        objective = Objective,
        severity = Severity,
        status = <<"open">>,
        escalation_tier = escalation_tier(Severity, Now, Now),
        template_id = template_for(Severity),
        owner = undefined,
        summary = undefined,
        postmortem_draft = undefined,
        created_at = Now,
        updated_at = Now,
        last_seen_at = Now,
        resolved_at = undefined,
        resolved_by = undefined
    }.

refresh_incident(Rec, Alert, Now) ->
    Severity = normalize_text(maps:get(severity, Alert, Rec#incident_response.severity)),
    Rec#incident_response{
        objective = normalize_text(maps:get(objective, Alert, Rec#incident_response.objective)),
        severity = Severity,
        status = case Rec#incident_response.status of
            <<"resolved">> -> <<"open">>;
            Current -> Current
        end,
        escalation_tier = escalation_tier(Severity, Rec#incident_response.created_at, Now),
        template_id = template_for(Severity),
        updated_at = Now,
        last_seen_at = Now,
        resolved_at = undefined,
        resolved_by = undefined
    }.

auto_resolve_incident(Rec, Now) ->
    Rec#incident_response{
        status = <<"resolved">>,
        summary = <<"Auto-resolved after objective returned within target">>,
        updated_at = Now,
        resolved_at = Now,
        resolved_by = <<"system">>
    }.

incident_to_map(#incident_response{} = Rec) ->
    Base = #{
        incident_id => Rec#incident_response.incident_id,
        source_alert_id => Rec#incident_response.source_alert_id,
        objective => Rec#incident_response.objective,
        severity => Rec#incident_response.severity,
        status => Rec#incident_response.status,
        escalation_tier => Rec#incident_response.escalation_tier,
        template_id => Rec#incident_response.template_id,
        created_at => Rec#incident_response.created_at,
        updated_at => Rec#incident_response.updated_at,
        last_seen_at => Rec#incident_response.last_seen_at
    },
    maybe_put(owner, Rec#incident_response.owner,
        maybe_put(summary, Rec#incident_response.summary,
            maybe_put(resolved_at, Rec#incident_response.resolved_at,
                maybe_put(resolved_by, Rec#incident_response.resolved_by,
                    maybe_put(postmortem_draft, Rec#incident_response.postmortem_draft, Base))))).

build_postmortem_draft(Rec, Resolver, Summary, Now) ->
    TemplateId = Rec#incident_response.template_id,
    Template = template_by_id(TemplateId),
    #{
        template_id => TemplateId,
        title => maps:get(title, Template, <<"Incident Post-Mortem">>),
        generated_at => Now,
        incident_id => Rec#incident_response.incident_id,
        objective => Rec#incident_response.objective,
        severity => Rec#incident_response.severity,
        owner => maybe_default(Rec#incident_response.owner, <<"unassigned">>),
        resolver => Resolver,
        summary => Summary,
        sections => [#{name => Section, content => <<>>} || Section <- maps:get(sections, Template, [])]
    }.

template_by_id(TemplateId) ->
    case lists:filter(fun(T) -> maps:get(template_id, T) =:= TemplateId end, templates()) of
        [Template | _] -> Template;
        [] -> #{title => <<"Incident Post-Mortem">>, sections => []}
    end.

template_for(<<"critical">>) -> <<"p1-major-incident">>;
template_for(<<"warning">>) -> <<"p2-degraded-service">>;
template_for(_) -> <<"p3-monitoring-only">>.

escalation_tier(Severity, OpenedAt, Now) ->
    AgeMs = erlang:max(0, Now - OpenedAt),
    case Severity of
        <<"critical">> when AgeMs >= 45 * 60 * 1000 -> 2;
        <<"critical">> when AgeMs >= 10 * 60 * 1000 -> 1;
        <<"warning">> when AgeMs >= 120 * 60 * 1000 -> 2;
        <<"warning">> when AgeMs >= 30 * 60 * 1000 -> 1;
        _ -> 0
    end.

incident_id(AlertId) ->
    iolist_to_binary([<<"inc-">>, AlertId]).

normalize_filters(Filters) ->
    #{
        status => normalize_optional_binary(maps:get(status, Filters, undefined)),
        severity => normalize_optional_binary(maps:get(severity, Filters, undefined)),
        objective => normalize_optional_binary(maps:get(objective, Filters, undefined)),
        limit => normalize_limit(maps:get(limit, Filters, ?DEFAULT_LIMIT), ?DEFAULT_LIMIT),
        offset => normalize_limit(maps:get(offset, Filters, 0), 0)
    }.

matches_filters(#incident_response{} = Rec, Filters) ->
    matches_exact(Rec#incident_response.status, maps:get(status, Filters)) andalso
    matches_exact(Rec#incident_response.severity, maps:get(severity, Filters)) andalso
    matches_exact(Rec#incident_response.objective, maps:get(objective, Filters)).

matches_exact(_Value, undefined) ->
    true;
matches_exact(Value, Filter) ->
    Value =:= Filter.

sort_desc(#{updated_at := L, incident_id := LId}, #{updated_at := R, incident_id := RId}) when L =:= R ->
    LId >= RId;
sort_desc(#{updated_at := L}, #{updated_at := R}) ->
    L >= R.

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

normalize_optional_binary(undefined) ->
    undefined;
normalize_optional_binary(<<>>) ->
    undefined;
normalize_optional_binary(Value) ->
    normalize_text(Value).

normalize_limit(Value, _Default) when is_integer(Value), Value >= 0 ->
    Value;
normalize_limit(_Value, Default) ->
    Default.

normalize_text(Value) when is_binary(Value) ->
    Value;
normalize_text(Value) when is_atom(Value) ->
    atom_to_binary(Value, utf8);
normalize_text(Value) when is_integer(Value) ->
    integer_to_binary(Value);
normalize_text(Value) ->
    iolist_to_binary(io_lib:format("~p", [Value])).

maybe_put(_Key, undefined, Map) ->
    Map;
maybe_put(Key, Value, Map) ->
    Map#{Key => Value}.

maybe_default(undefined, Default) ->
    Default;
maybe_default(Value, _Default) ->
    Value.
