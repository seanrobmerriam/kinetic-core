%% @doc HTTP handler for the natural-language query gateway (TASK-078).
%%
%% Routes:
%%   POST /api/v1/insights/queries
%%     body: {submitted_by, text}
%%   GET  /api/v1/insights/queries
%%     query: ?limit=N
%%   GET  /api/v1/insights/queries/:id
%%   POST /api/v1/insights/queries/:id/execute
-module(cb_nl_query_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").
-include_lib("cb_insights/include/cb_insights.hrl").

-export([init/2]).

init(Req, State) ->
    Method = cowboy_req:method(Req),
    Id     = cowboy_req:binding(id, Req),
    Action = cowboy_req:binding(action, Req),
    handle(Method, Id, Action, Req, State).

handle(<<"POST">>, undefined, undefined, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{submitted_by := Who, text := Text}, _}
                when is_binary(Who), is_binary(Text) ->
            case cb_nl_query:submit(Who, Text) of
                {ok, Id, Intent} ->
                    reply(201, #{query_id => Id, intent => Intent}, Req2, State);
                {error, R} ->
                    error_reply(400, R, Req2, State)
            end;
        _ ->
            error_reply(400, <<"Missing submitted_by, text">>, Req2, State)
    end;

handle(<<"GET">>, undefined, undefined, Req, State) ->
    Qs = cowboy_req:parse_qs(Req),
    Limit = parse_int(proplists:get_value(<<"limit">>, Qs), 20),
    Qs2 = cb_nl_query:list_recent(Limit),
    reply(200, #{queries => [q_to_map(Q) || Q <- Qs2]}, Req, State);

handle(<<"GET">>, Id, undefined, Req, State) ->
    case cb_nl_query:get(Id) of
        {ok, Q}            -> reply(200, q_to_map(Q), Req, State);
        {error, not_found} -> error_reply(404, <<"Query not found">>, Req, State)
    end;

handle(<<"POST">>, Id, <<"execute">>, Req, State) ->
    case cb_nl_query:execute(Id) of
        {ok, Result}           -> reply(200, #{result => Result}, Req, State);
        {error, not_found}     -> error_reply(404, <<"Query not found">>, Req, State);
        {error, Reason}        -> error_reply(409, Reason, Req, State)
    end;

handle(_, _, _, Req, State) ->
    error_reply(405, <<"Method not allowed">>, Req, State).

q_to_map(Q) ->
    #{query_id     => Q#nl_query.query_id,
      submitted_by => Q#nl_query.submitted_by,
      raw_text     => Q#nl_query.raw_text,
      intent       => Q#nl_query.intent,
      params       => Q#nl_query.params,
      status       => Q#nl_query.status,
      created_at   => Q#nl_query.created_at,
      updated_at   => Q#nl_query.updated_at}.

parse_int(undefined, D) -> D;
parse_int(Bin, D) when is_binary(Bin) ->
    try binary_to_integer(Bin) of
        N when N >= 1 -> N;
        _             -> D
    catch _:_ -> D
    end.

reply(Code, Body, Req, State) ->
    R = cowboy_req:reply(Code, headers(), jsone:encode(Body), Req),
    {ok, R, State}.

headers() ->
    #{<<"content-type">> => <<"application/json">>}.

error_reply(Code, Reason, Req, State) when is_atom(Reason) ->
    error_reply(Code, atom_to_binary(Reason, utf8), Req, State);
error_reply(Code, Reason, Req, State) ->
    R = cowboy_req:reply(Code, headers(),
            jsone:encode(#{error => Reason}), Req),
    {ok, R, State}.
