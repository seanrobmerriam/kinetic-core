%% @doc Bulk Export Handler
%%
%% Handler for `GET /api/v1/export/:resource`
%%
%% Supported resources: parties | accounts | transactions | ledger | events
%%
%% Query parameters:
%%   format — csv (only supported format, json planned)
%%   account_id — optional filter for ledger exports
%%   from — optional Unix timestamp ms (for future date filtering)
%%   to — optional Unix timestamp ms (for future date filtering)
%%
%% Returns CSV binary with appropriate content-type header.
-module(cb_export_handler).

-export([init/2]).

-spec init(cowboy_req:req(), any()) -> {ok, cowboy_req:req(), any()}.
init(Req, State) ->
    Method = cowboy_req:method(Req),
    Resource = cowboy_req:binding(resource, Req),
    handle(Method, Resource, Req, State).

handle(<<"GET">>, Resource, Req, State) ->
    Qs = cowboy_req:parse_qs(Req),
    Format = proplists:get_value(<<"format">>, Qs, <<"csv">>),
    Filters = parse_filters(Qs),
    case export_resource(Resource, Format, Filters) of
        {ok, Binary, ContentType} ->
            Headers = #{
                <<"content-type">> => ContentType,
                <<"content-disposition">> => <<"attachment; filename=\"", (atom_to_binary(Resource))/binary, ".csv\"">>
            },
            Req2 = cowboy_req:reply(200, maps:merge(Headers, cb_cors:headers()), Binary, Req),
            {ok, Req2, State};
        {error, Reason} ->
            {Status, ErrorAtom, Message} = cb_http_errors:to_response(Reason),
            Resp = #{error => ErrorAtom, message => Message},
            Headers = maps:merge(#{<<"content-type">> => <<"application/json">>}, cb_cors:headers()),
            Req2 = cowboy_req:reply(Status, Headers, jsone:encode(Resp), Req),
            {ok, Req2, State}
    end;

handle(<<"OPTIONS">>, _Resource, Req, State) ->
    Req2 = cb_cors:reply_preflight(Req),
    {ok, Req2, State};

handle(_, _Resource, Req, State) ->
    {_Code405, _Hdrs405, _Body405} = cb_http_errors:to_response_with_metrics(method_not_allowed),
    Req2 = cowboy_req:reply(_Code405, _Hdrs405, _Body405, Req),
    {ok, Req2, State}.

%% Parse optional filter params from query string.
-spec parse_filters(proplists:proplist()) -> map().
parse_filters(Qs) ->
    Filters0 = #{},
    Filters1 = case proplists:get_value(<<"account_id">>, Qs) of
        undefined -> Filters0;
        AccId     -> Filters0#{account_id => AccId}
    end,
    Filters2 = case proplists:get_value(<<"from">>, Qs) of
        undefined -> Filters1;
        FromVal   -> Filters1#{from => binary_to_integer(FromVal)}
    end,
    case proplists:get_value(<<"to">>, Qs) of
        undefined -> Filters2;
        ToVal     -> Filters2#{to => binary_to_integer(ToVal)}
    end.

-spec export_resource(binary(), binary(), map()) -> {ok, binary(), binary()} | {error, atom()}.
export_resource(<<"parties">>, <<"csv">>, _Filters) ->
    cb_exports:export_resource(parties, #{});
export_resource(<<"accounts">>, <<"csv">>, _Filters) ->
    cb_exports:export_resource(accounts, #{});
export_resource(<<"transactions">>, <<"csv">>, _Filters) ->
    cb_exports:export_resource(transactions, #{});
export_resource(<<"ledger">>, <<"csv">>, Filters) ->
    cb_exports:export_resource(ledger, Filters);
export_resource(<<"events">>, <<"csv">>, _Filters) ->
    cb_exports:export_resource(events, #{});
export_resource(Resource, Format, _Filters) ->
    {error, {unsupported_format, Resource, Format}}.