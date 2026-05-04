%% @doc HTTP handler for ledger propagation tracking (TASK-070).
%%
%% Routes:
%%   GET  /api/v1/ledger/propagation/targets               — list targets
%%   POST /api/v1/ledger/propagation/targets               — register target
%%   POST /api/v1/ledger/propagation/targets/:target_id/disable — disable target
%%   POST /api/v1/ledger/propagation/events                — record event
%%   GET  /api/v1/ledger/propagation/entries/:entry_id/events    — list events
%%   GET  /api/v1/ledger/propagation/entries/:entry_id/freshness — freshness
-module(cb_ledger_propagation_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

init(Req, State) ->
    Method   = cowboy_req:method(Req),
    Resource = cowboy_req:binding(resource, Req),
    Id       = cowboy_req:binding(id, Req),
    Action   = cowboy_req:binding(action, Req),
    handle(Method, Resource, Id, Action, Req, State).

handle(<<"GET">>, <<"targets">>, undefined, undefined, Req, State) ->
    Targets = cb_ledger_propagation:list_targets(),
    Body = jsone:encode(#{targets => [target_to_map(T) || T <- Targets]}),
    Req2 = cowboy_req:reply(200, headers(), Body, Req),
    {ok, Req2, State};

handle(<<"POST">>, <<"targets">>, undefined, undefined, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{name := Name, sla_ms := Sla}, _} when is_integer(Sla) ->
            case cb_ledger_propagation:register_target(Name, Sla) of
                {ok, TargetId} ->
                    R = cowboy_req:reply(201, headers(),
                            jsone:encode(#{target_id => TargetId}), Req2),
                    {ok, R, State};
                {error, Reason} ->
                    error_reply(400, Reason, Req2, State)
            end;
        _ ->
            error_reply(400, <<"Missing required fields: name, sla_ms">>, Req2, State)
    end;

handle(<<"POST">>, <<"targets">>, TargetId, <<"disable">>, Req, State) ->
    case cb_ledger_propagation:disable_target(TargetId) of
        ok ->
            R = cowboy_req:reply(200, headers(),
                    jsone:encode(#{status => <<"disabled">>}), Req),
            {ok, R, State};
        {error, not_found} ->
            error_reply(404, <<"Target not found">>, Req, State)
    end;

handle(<<"POST">>, <<"events">>, undefined, undefined, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{entry_id := EntryId, target := TargetName, posted_at := PostedAt}, _}
                when is_integer(PostedAt) ->
            case cb_ledger_propagation:record_propagation(EntryId, TargetName, PostedAt) of
                {ok, EventId} ->
                    R = cowboy_req:reply(201, headers(),
                            jsone:encode(#{event_id => EventId}), Req2),
                    {ok, R, State};
                {error, Reason} ->
                    error_reply(400, Reason, Req2, State)
            end;
        _ ->
            error_reply(400,
                <<"Missing required fields: entry_id, target, posted_at">>,
                Req2, State)
    end;

handle(<<"GET">>, <<"entries">>, EntryId, <<"events">>, Req, State) ->
    Events = cb_ledger_propagation:list_events_for_entry(EntryId),
    Body = jsone:encode(#{events => [event_to_map(E) || E <- Events]}),
    Req2 = cowboy_req:reply(200, headers(), Body, Req),
    {ok, Req2, State};

handle(<<"GET">>, <<"entries">>, EntryId, <<"freshness">>, Req, State) ->
    {ok, Result} = cb_ledger_propagation:freshness(EntryId),
    Req2 = cowboy_req:reply(200, headers(), jsone:encode(Result), Req),
    {ok, Req2, State};

handle(_, _, _, _, Req, State) ->
    error_reply(405, <<"Method not allowed">>, Req, State).

target_to_map(T) ->
    #{target_id   => T#propagation_target.target_id,
      target_name => T#propagation_target.target_name,
      sla_ms      => T#propagation_target.sla_ms,
      enabled     => T#propagation_target.enabled,
      created_at  => T#propagation_target.created_at}.

event_to_map(E) ->
    #{event_id      => E#propagation_event.event_id,
      entry_id      => E#propagation_event.entry_id,
      target_name   => E#propagation_event.target_name,
      posted_at     => E#propagation_event.posted_at,
      propagated_at => E#propagation_event.propagated_at,
      latency_ms    => E#propagation_event.latency_ms}.

headers() ->
    #{<<"content-type">> => <<"application/json">>}.

error_reply(Code, Reason, Req, State) when is_atom(Reason) ->
    error_reply(Code, atom_to_binary(Reason, utf8), Req, State);
error_reply(Code, Reason, Req, State) ->
    R = cowboy_req:reply(Code, headers(),
            jsone:encode(#{error => Reason}), Req),
    {ok, R, State}.
