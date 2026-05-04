%% @doc HTTP handler for cryptographic audit chain (TASK-073).
%%
%% Routes:
%%   GET  /api/v1/audit/chain/links              — list links in range (?from&to)
%%   POST /api/v1/audit/chain/links              — append link for entry
%%   GET  /api/v1/audit/chain/links/:link_id     — get link by id
%%   GET  /api/v1/audit/chain/head               — current head link
%%   POST /api/v1/audit/chain/verify             — verify entire chain
-module(cb_audit_chain_handler).
-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

init(Req, State) ->
    Method   = cowboy_req:method(Req),
    Resource = cowboy_req:binding(resource, Req),
    Id       = cowboy_req:binding(id, Req),
    handle(Method, Resource, Id, Req, State).

handle(<<"GET">>, <<"links">>, undefined, Req, State) ->
    Qs = cowboy_req:parse_qs(Req),
    From = parse_int(proplists:get_value(<<"from">>, Qs), 1),
    To   = parse_int(proplists:get_value(<<"to">>, Qs), max_seq()),
    Links = cb_audit_chain:list_links(From, To),
    R = cowboy_req:reply(200, headers(),
            jsone:encode(#{links => [link_to_map(L) || L <- Links]}), Req),
    {ok, R, State};

handle(<<"POST">>, <<"links">>, undefined, Req, State) ->
    {ok, Body, Req2} = cowboy_req:read_body(Req),
    case jsone:try_decode(Body, [{keys, atom}]) of
        {ok, #{entry_id := EntryId, posted_at := PostedAt, amount := Amount}, _}
                when is_integer(PostedAt), is_integer(Amount) ->
            case cb_audit_chain:append(EntryId, PostedAt, Amount) of
                {ok, LinkId, Hash} ->
                    R = cowboy_req:reply(201, headers(),
                            jsone:encode(#{link_id => LinkId,
                                           link_hash => Hash}), Req2),
                    {ok, R, State};
                {error, Reason} ->
                    error_reply(400, Reason, Req2, State)
            end;
        _ ->
            error_reply(400,
                <<"Missing required fields: entry_id, posted_at, amount">>,
                Req2, State)
    end;

handle(<<"GET">>, <<"links">>, LinkId, Req, State) ->
    case cb_audit_chain:get_link(LinkId) of
        {ok, L} ->
            R = cowboy_req:reply(200, headers(),
                    jsone:encode(link_to_map(L)), Req),
            {ok, R, State};
        {error, not_found} ->
            error_reply(404, <<"Link not found">>, Req, State)
    end;

handle(<<"GET">>, <<"head">>, undefined, Req, State) ->
    case cb_audit_chain:head() of
        {ok, L} ->
            R = cowboy_req:reply(200, headers(),
                    jsone:encode(link_to_map(L)), Req),
            {ok, R, State};
        none ->
            R = cowboy_req:reply(200, headers(),
                    jsone:encode(#{head => null}), Req),
            {ok, R, State}
    end;

handle(<<"POST">>, <<"verify">>, undefined, Req, State) ->
    case cb_audit_chain:verify_chain() of
        {ok, Summary} ->
            R = cowboy_req:reply(200, headers(),
                    jsone:encode(maps:merge(#{verified => true}, Summary)), Req),
            {ok, R, State};
        {error, Detail} ->
            R = cowboy_req:reply(409, headers(),
                    jsone:encode(maps:merge(#{verified => false}, Detail)), Req),
            {ok, R, State}
    end;

handle(_, _, _, Req, State) ->
    error_reply(405, <<"Method not allowed">>, Req, State).

max_seq() ->
    case cb_audit_chain:head() of
        {ok, H} -> H#audit_chain_link.sequence;
        none    -> 1
    end.

parse_int(undefined, Default) -> Default;
parse_int(Bin, Default) when is_binary(Bin) ->
    try binary_to_integer(Bin) of
        N when N >= 1 -> N;
        _             -> Default
    catch
        _:_ -> Default
    end.

link_to_map(L) ->
    #{link_id    => L#audit_chain_link.link_id,
      sequence   => L#audit_chain_link.sequence,
      entry_id   => L#audit_chain_link.entry_id,
      prev_hash  => L#audit_chain_link.prev_hash,
      link_hash  => L#audit_chain_link.link_hash,
      created_at => L#audit_chain_link.created_at}.

headers() ->
    #{<<"content-type">> => <<"application/json">>}.

error_reply(Code, Reason, Req, State) when is_atom(Reason) ->
    error_reply(Code, atom_to_binary(Reason, utf8), Req, State);
error_reply(Code, Reason, Req, State) ->
    R = cowboy_req:reply(Code, headers(),
            jsone:encode(#{error => Reason}), Req),
    {ok, R, State}.
