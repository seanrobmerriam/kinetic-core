%% @doc Channel Feature Flags Handler
%%
%% Endpoints:
%%   GET  /api/v1/channel-features/:channel
%%   GET  /api/v1/channel-features/:channel/:feature
%%   PUT  /api/v1/channel-features/:channel/:feature
-module(cb_channel_features_handler).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method   = cowboy_req:method(Req),
    ChannelB = cowboy_req:binding(channel, Req),
    Feature  = cowboy_req:binding(feature, Req),
    handle(Method, ChannelB, Feature, Req, State).

handle(<<"GET">>, ChannelBin, undefined, Req, State) ->
    case parse_channel(ChannelBin) of
        {ok, Channel} ->
            {ok, Flags} = cb_channel_features:list_for_channel(Channel),
            json_reply(200, [flag_to_json(F) || F <- Flags], Req, State);
        {error, _} ->
            error_reply(invalid_channel, Req, State)
    end;

handle(<<"GET">>, ChannelBin, Feature, Req, State) ->
    case parse_channel(ChannelBin) of
        {ok, Channel} ->
            case cb_channel_features:get_flag(Channel, Feature) of
                {ok, Flag}         -> json_reply(200, flag_to_json(Flag), Req, State);
                {error, not_found} -> error_reply(not_found, Req, State)
            end;
        {error, _} ->
            error_reply(invalid_channel, Req, State)
    end;

handle(<<"PUT">>, ChannelBin, Feature, Req, State) ->
    case parse_channel(ChannelBin) of
        {ok, Channel} ->
            {ok, Body, Req2} = cowboy_req:read_body(Req),
            case jsone:try_decode(Body) of
                {ok, Decoded, _} ->
                    Enabled = maps:get(<<"enabled">>, Decoded, false),
                    case cb_channel_features:set_flag(Channel, Feature, Enabled) of
                        {ok, Flag}   -> json_reply(200, flag_to_json(Flag), Req2, State);
                        {error, R}   -> error_reply(R, Req2, State)
                    end;
                _ ->
                    error_reply(missing_required_field, Req, State)
            end;
        {error, _} ->
            error_reply(invalid_channel, Req, State)
    end;

handle(<<"OPTIONS">>, _Channel, _Feature, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _Channel, _Feature, Req, State) ->
    {Code, Hdrs, Body} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(Code, Hdrs, Body, Req),
    {ok, Req2, State}.

flag_to_json(#channel_feature_flag{} = F) ->
    #{
        channel    => F#channel_feature_flag.channel,
        feature    => F#channel_feature_flag.feature,
        enabled    => F#channel_feature_flag.enabled,
        updated_at => F#channel_feature_flag.updated_at
    }.

json_reply(Status, Body, Req, State) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Body), Req),
    {ok, Req2, State}.

error_reply(Reason, Req, State) ->
    {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
    Resp = #{error => ErrorAtom, message => Message},
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
    {ok, Req2, State}.

parse_channel(<<"web">>)    -> {ok, web};
parse_channel(<<"mobile">>) -> {ok, mobile};
parse_channel(<<"branch">>) -> {ok, branch};
parse_channel(<<"atm">>)    -> {ok, atm};
parse_channel(_)            -> {error, invalid_channel}.
