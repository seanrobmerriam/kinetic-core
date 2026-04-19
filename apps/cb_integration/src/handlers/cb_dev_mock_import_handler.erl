%% @doc Development-only mock data import endpoint.

-module(cb_dev_mock_import_handler).

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    handle(Method, Req, State).

handle(<<"GET">>, Req, State) ->
    Reply = #{enabled => dev_tools_enabled()},
    Req2 = reply_json(200, Reply, Req),
    {ok, Req2, State};

handle(<<"POST">>, Req, State) ->
    case dev_tools_enabled() of
        false ->
            {Status, ErrorAtom, Message} = cb_http_errors:to_response(dev_tools_disabled),
            Resp = #{error => ErrorAtom, message => Message},
            Req2 = reply_json(Status, Resp, Req),
            {ok, Req2, State};
        true ->
            case cb_mock_data_importer:import() of
                {ok, Summary} ->
                    Resp = #{status => <<"ok">>, summary => Summary},
                    Req2 = reply_json(200, Resp, Req),
                    {ok, Req2, State};
                {error, Reason} ->
                    {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
                    Resp = #{error => ErrorAtom, message => Message},
                    Req2 = reply_json(Status, Resp, Req),
                    {ok, Req2, State}
            end
    end;

handle(<<"OPTIONS">>, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, Req, State) ->
    Req2 = reply_json(405, #{error => <<"method_not_allowed">>}, Req),
    {ok, Req2, State}.

dev_tools_enabled() ->
    application:get_env(cb_integration, enable_dev_tools, false).

reply_json(Status, Payload, Req) ->
    Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
    cowboy_req:reply(Status, Headers, jsone:encode(Payload), Req).
