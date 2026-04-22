%% @doc Channel Activity Log Handler
%%
%% Handler for `/api/v1/channel-activity` endpoint.
%%
%% <h2>REST API Endpoints</h2>
%%
%% <ul>
%%   <li><b>GET /api/v1/channel-activity</b> - List recent channel activity</li>
%%   <li><b>OPTIONS</b> - CORS preflight</li>
%% </ul>
%%
%% <h2>Query Parameters</h2>
%%
%% <ul>
%%   <li><b>channel</b> - Filter by channel type (web, mobile, branch, atm)</li>
%%   <li><b>party_id</b> - Filter by party UUID</li>
%%   <li><b>limit</b> - Max entries to return (default: 50, max: 200)</li>
%% </ul>
-module(cb_channel_activity_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-define(DEFAULT_LIMIT, 50).
-define(MAX_LIMIT, 200).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    handle(Method, Req, State).

handle(<<"GET">>, Req, State) ->
    Qs       = cowboy_req:parse_qs(Req),
    Channel  = proplists:get_value(<<"channel">>,  Qs, undefined),
    PartyId  = proplists:get_value(<<"party_id">>, Qs, undefined),
    LimitBin = proplists:get_value(<<"limit">>,    Qs, undefined),
    Limit    = parse_limit(LimitBin),
    Entries  = fetch_entries(Channel, PartyId, Limit),
    Resp = #{
        entries => [activity_to_json(E) || E <- Entries],
        count   => length(Entries)
    },
    json_reply(200, Resp, Req, State);

handle(<<"OPTIONS">>, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(405, Headers, <<"{\"error\":\"method_not_allowed\"}">>, Req),
    {ok, Req2, State}.

%% Internal helpers

fetch_entries(undefined, undefined, Limit) ->
    cb_channel_activity:list_recent(Limit);
fetch_entries(ChannelBin, undefined, Limit) ->
    case parse_channel(ChannelBin) of
        {ok, Channel} ->
            All = cb_channel_activity:list_for_channel(Channel),
            lists:sublist(All, Limit);
        _ ->
            []
    end;
fetch_entries(undefined, PartyId, Limit) ->
    All = cb_channel_activity:list_for_party(PartyId),
    lists:sublist(All, Limit);
fetch_entries(ChannelBin, PartyId, Limit) ->
    case parse_channel(ChannelBin) of
        {ok, Channel} ->
            All = cb_channel_activity:list_for_channel(Channel),
            Filtered = [E || E <- All, E#channel_activity.party_id =:= PartyId],
            lists:sublist(Filtered, Limit);
        _ ->
            []
    end.

activity_to_json(#channel_activity{} = E) ->
    #{
        log_id      => E#channel_activity.log_id,
        channel     => format_channel(E#channel_activity.channel),
        party_id    => null_or_val(E#channel_activity.party_id),
        action      => E#channel_activity.action,
        endpoint    => E#channel_activity.endpoint,
        status_code => E#channel_activity.status_code,
        created_at  => E#channel_activity.created_at
    }.

format_channel(undefined) -> null;
format_channel(Ch)        -> Ch.

null_or_val(undefined) -> null;
null_or_val(Val)        -> Val.

json_reply(Status, Body, Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Body), Req),
    {ok, Req2, State}.

parse_limit(undefined) -> ?DEFAULT_LIMIT;
parse_limit(Bin) ->
    case catch binary_to_integer(Bin) of
        N when is_integer(N), N > 0 -> min(N, ?MAX_LIMIT);
        _                           -> ?DEFAULT_LIMIT
    end.

parse_channel(<<"web">>)    -> {ok, web};
parse_channel(<<"mobile">>) -> {ok, mobile};
parse_channel(<<"branch">>) -> {ok, branch};
parse_channel(<<"atm">>)    -> {ok, atm};
parse_channel(_)            -> {error, invalid_channel}.
