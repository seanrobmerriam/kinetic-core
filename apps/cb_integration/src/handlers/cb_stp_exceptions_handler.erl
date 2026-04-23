%% @doc HTTP handler for exception SLA endpoints.
%%
%% Routes:
%%   GET  /v1/stp/exceptions/overdue
%%   POST /v1/stp/exceptions/:id/escalate
%%   POST /v1/stp/exceptions/:id/sla
-module(cb_stp_exceptions_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

init(Req, State) ->
    Method = cowboy_req:method(Req),
    Action = cowboy_req:binding(action, Req),
    ItemId = cowboy_req:binding(item_id, Req),
    handle(Method, Action, ItemId, Req, State).

%% GET /v1/stp/exceptions/overdue
handle(<<"GET">>, <<"overdue">>, undefined, Req, State) ->
    Items = cb_exception_sla:check_overdue(),
    Req2 = cowboy_req:reply(200, headers(),
               jsone:encode(#{overdue => [item_to_map(I) || I <- Items]}), Req),
    {ok, Req2, State};

%% POST /v1/stp/exceptions/:id/escalate
handle(<<"POST">>, <<"escalate">>, ItemId, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    Tier = case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{tier := T}, _} when T =:= 1; T =:= 2 -> T;
        _ -> 1
    end,
    case cb_exception_sla:escalate(ItemId, Tier) of
        {ok, Item} ->
            Req3 = cowboy_req:reply(200, headers(),
                       jsone:encode(item_to_map(Item)), Req2),
            {ok, Req3, State};
        {error, not_found} ->
            Req3 = cowboy_req:reply(404, headers(),
                       jsone:encode(#{error => <<"not_found">>}), Req2),
            {ok, Req3, State};
        {error, already_resolved} ->
            Req3 = cowboy_req:reply(409, headers(),
                       jsone:encode(#{error => <<"already_resolved">>}), Req2),
            {ok, Req3, State}
    end;

%% POST /v1/stp/exceptions/:id/sla
handle(<<"POST">>, <<"sla">>, ItemId, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{sla_minutes := Mins}, _} when is_integer(Mins), Mins > 0 ->
            case cb_exception_sla:set_sla(ItemId, Mins) of
                {ok, Item} ->
                    Req3 = cowboy_req:reply(200, headers(),
                               jsone:encode(item_to_map(Item)), Req2),
                    {ok, Req3, State};
                {error, not_found} ->
                    Req3 = cowboy_req:reply(404, headers(),
                               jsone:encode(#{error => <<"not_found">>}), Req2),
                    {ok, Req3, State}
            end;
        _ ->
            Req3 = cowboy_req:reply(400, headers(),
                       jsone:encode(#{error => <<"bad_request">>,
                                      message => <<"sla_minutes required">>}), Req2),
            {ok, Req3, State}
    end;

handle(_, _, _, Req, State) ->
    Req2 = cowboy_req:reply(405, headers(), <<>>, Req),
    {ok, Req2, State}.

item_to_map(#exception_item{
    item_id = Id, payment_id = Pid, reason = Reason,
    status = Status, sla_minutes = SlaMins,
    sla_deadline = SlaDeadline, escalation_tier = Tier,
    created_at = CreAt, updated_at = UpdAt
}) ->
    #{
        item_id         => Id,
        payment_id      => Pid,
        reason          => Reason,
        status          => Status,
        sla_minutes     => SlaMins,
        sla_deadline    => SlaDeadline,
        escalation_tier => Tier,
        created_at      => CreAt,
        updated_at      => UpdAt
    }.

headers() ->
    maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()).
