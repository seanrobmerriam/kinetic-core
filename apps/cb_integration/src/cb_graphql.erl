%% @doc GraphQL Execution Engine
%%
%% Implements a minimal but complete GraphQL executor supporting high-value
%% read queries against the core banking domain. No external libraries required.
%%
%% <h2>Supported Operations</h2>
%%
%% <ul>
%%   <li>`party(id: ID!)' - Fetch a single party by ID</li>
%%   <li>`account(id: ID!)' - Fetch a single account by ID</li>
%%   <li>`parties(page: Int, pageSize: Int)' - Paginated party list</li>
%%   <li>`accounts(partyId: ID, page: Int, pageSize: Int)' - Paginated account list</li>
%% </ul>
%%
%% <h2>Query Format</h2>
%%
%% Standard GraphQL query syntax is supported:
%%
%% ```
%% { party(id: "uuid") { id fullName email status } }
%% query { parties(page: 1, pageSize: 10) { id fullName } }
%% '''
%%
%% <h2>Response Format</h2>
%%
%% Returns `{ok, #{<<"data">> => ..., <<"errors">> => []}}' on success or
%% `{error, Errors}' on parse/execution failure.
%%
%% @see cb_party
%% @see cb_accounts
-module(cb_graphql).

-include("../../cb_ledger/include/cb_ledger.hrl").

-export([execute/1, schema_sdl/0]).

-type token() :: lbrace | rbrace | lparen | rparen | colon | comma
               | {ident, binary()} | {string, binary()} | {int, integer()}.

-type args() :: #{binary() => binary() | integer()}.

-type selection() :: #{
    name          := binary(),
    arguments     := args(),
    selection_set := [selection()]
}.

-type document() :: #{
    operation_type := query,
    selection_set  := [selection()]
}.

%% @doc Parse and execute a GraphQL query string.
%%
%% @param QueryBin Raw GraphQL query bytes from the HTTP request body.
%%
%% @returns `{ok, ResponseMap}' where ResponseMap has `<<"data">>' and
%%          optionally `<<"errors">>' keys, following the GraphQL spec.
%%          Returns `{error, Errors}' on parse failure.
-spec execute(binary()) ->
    {ok, #{binary() => term()}} | {error, [#{binary() => binary()}]}.
execute(QueryBin) ->
    try
        Doc = parse(QueryBin),
        Data = resolve_document(Doc),
        {ok, #{<<"data">> => Data, <<"errors">> => []}}
    catch
        throw:{graphql_error, Msg} ->
            {error, [#{<<"message">> => Msg}]};
        error:badarg ->
            {error, [#{<<"message">> => <<"Invalid argument type">>}]};
        error:Reason ->
            Msg = iolist_to_binary(io_lib:format("~p", [Reason])),
            {error, [#{<<"message">> => Msg}]}
    end.

%% @doc Return the schema SDL string for introspection endpoints.
-spec schema_sdl() -> binary().
schema_sdl() ->
    <<"type Query {\n"
      "  party(id: ID!): Party\n"
      "  account(id: ID!): Account\n"
      "  parties(page: Int, pageSize: Int): PartyPage!\n"
      "  accounts(partyId: ID, page: Int, pageSize: Int): AccountPage!\n"
      "}\n\n"
      "type Party {\n"
      "  id: ID!\n"
      "  fullName: String!\n"
      "  email: String!\n"
      "  status: String!\n"
      "  kycStatus: String!\n"
      "  onboardingStatus: String!\n"
      "  createdAt: Int!\n"
      "  updatedAt: Int!\n"
      "}\n\n"
      "type Account {\n"
      "  id: ID!\n"
      "  partyId: ID!\n"
      "  name: String!\n"
      "  currency: String!\n"
      "  balance: Int!\n"
      "  status: String!\n"
      "  createdAt: Int!\n"
      "  updatedAt: Int!\n"
      "}\n\n"
      "type PartyPage {\n"
      "  items: [Party!]!\n"
      "  total: Int!\n"
      "  page: Int!\n"
      "  pageSize: Int!\n"
      "}\n\n"
      "type AccountPage {\n"
      "  items: [Account!]!\n"
      "  total: Int!\n"
      "  page: Int!\n"
      "  pageSize: Int!\n"
      "}\n">>.

%% ---------------------------------------------------------------------------
%% Internal: parsing
%% ---------------------------------------------------------------------------

-spec parse(binary()) -> document().
parse(Bin) ->
    Tokens = tokenize(Bin),
    {Doc, []} = parse_document(Tokens),
    Doc.

-spec tokenize(binary()) -> [token()].
tokenize(<<>>) -> [];
tokenize(<<C, Rest/binary>>) when C =:= $\s; C =:= $\t; C =:= $\n; C =:= $\r ->
    tokenize(Rest);
tokenize(<<$#, Rest/binary>>) ->
    %% Skip comment line
    tokenize(skip_line(Rest));
tokenize(<<${, Rest/binary>>) -> [lbrace  | tokenize(Rest)];
tokenize(<<$}, Rest/binary>>) -> [rbrace  | tokenize(Rest)];
tokenize(<<$(, Rest/binary>>) -> [lparen  | tokenize(Rest)];
tokenize(<<$), Rest/binary>>) -> [rparen  | tokenize(Rest)];
tokenize(<<$:, Rest/binary>>) -> [colon   | tokenize(Rest)];
tokenize(<<$,, Rest/binary>>) -> [comma   | tokenize(Rest)];
tokenize(<<$", Rest/binary>>) ->
    {Str, Rest2} = scan_string(Rest, <<>>),
    [{string, Str} | tokenize(Rest2)];
tokenize(<<C, Rest/binary>>) when C >= $0, C =< $9 ->
    {Num, Rest2} = scan_int(Rest, <<C>>),
    [{int, binary_to_integer(Num)} | tokenize(Rest2)];
tokenize(<<C, Rest/binary>>) when (C >= $a andalso C =< $z);
                                   (C >= $A andalso C =< $Z);
                                   C =:= $_ ->
    {Id, Rest2} = scan_ident(Rest, <<C>>),
    [{ident, Id} | tokenize(Rest2)].

skip_line(<<$\n, Rest/binary>>) -> Rest;
skip_line(<<_, Rest/binary>>)   -> skip_line(Rest);
skip_line(<<>>)                  -> <<>>.

scan_string(<<$", Rest/binary>>, Acc) ->
    {Acc, Rest};
scan_string(<<$\\, $", Rest/binary>>, Acc) ->
    scan_string(Rest, <<Acc/binary, $">>);
scan_string(<<C, Rest/binary>>, Acc) ->
    scan_string(Rest, <<Acc/binary, C>>);
scan_string(<<>>, Acc) ->
    {Acc, <<>>}.

scan_int(<<C, Rest/binary>>, Acc) when C >= $0, C =< $9 ->
    scan_int(Rest, <<Acc/binary, C>>);
scan_int(Rest, Acc) ->
    {Acc, Rest}.

scan_ident(<<C, Rest/binary>>, Acc) when (C >= $a andalso C =< $z);
                                          (C >= $A andalso C =< $Z);
                                          (C >= $0 andalso C =< $9);
                                          C =:= $_ ->
    scan_ident(Rest, <<Acc/binary, C>>);
scan_ident(Rest, Acc) ->
    {Acc, Rest}.

-spec parse_document([token()]) -> {document(), [token()]}.
parse_document([{ident, <<"query">>} | Tokens]) ->
    parse_document(drop_leading_ident(Tokens));
parse_document([{ident, <<"mutation">>} | _]) ->
    throw({graphql_error, <<"Mutations are not supported">>});
parse_document([lbrace | Tokens]) ->
    {Fields, [rbrace | Rest]} = parse_selection_set_fields(Tokens, []),
    {#{operation_type => query, selection_set => Fields}, Rest};
parse_document(_) ->
    throw({graphql_error, <<"Expected '{' at start of document">>}).

%% Drop an optional operation name identifier before '{'
drop_leading_ident([{ident, _} | [lbrace | _] = Rest]) -> Rest;
drop_leading_ident(Tokens) -> Tokens.

-spec parse_selection_set_fields([token()], [selection()]) ->
    {[selection()], [token()]}.
parse_selection_set_fields([rbrace | _] = Tokens, Acc) ->
    {lists:reverse(Acc), Tokens};
parse_selection_set_fields([{ident, Name} | Tokens], Acc) ->
    {Args, Tokens2}   = maybe_parse_args(Tokens),
    {SelSet, Tokens3} = maybe_parse_selection_set(Tokens2),
    Field = #{name => Name, arguments => Args, selection_set => SelSet},
    Tokens4 = skip_comma(Tokens3),
    parse_selection_set_fields(Tokens4, [Field | Acc]);
parse_selection_set_fields([], Acc) ->
    {lists:reverse(Acc), []}.

-spec maybe_parse_args([token()]) -> {args(), [token()]}.
maybe_parse_args([lparen | Tokens]) ->
    parse_args(Tokens, #{});
maybe_parse_args(Tokens) ->
    {#{}, Tokens}.

-spec parse_args([token()], args()) -> {args(), [token()]}.
parse_args([rparen | Rest], Acc) ->
    {Acc, Rest};
parse_args([{ident, Key}, colon, {string, Val} | Tokens], Acc) ->
    parse_args(skip_comma(Tokens), Acc#{Key => Val});
parse_args([{ident, Key}, colon, {int, Val} | Tokens], Acc) ->
    parse_args(skip_comma(Tokens), Acc#{Key => Val});
parse_args([{ident, Key}, colon, {ident, <<"null">>} | Tokens], Acc) ->
    parse_args(skip_comma(Tokens), Acc#{Key => null});
parse_args([{ident, Key}, colon, {ident, Val} | Tokens], Acc) ->
    parse_args(skip_comma(Tokens), Acc#{Key => Val});
parse_args(Tokens, Acc) ->
    {Acc, skip_to(rparen, Tokens)}.

-spec maybe_parse_selection_set([token()]) -> {[selection()], [token()]}.
maybe_parse_selection_set([lbrace | Tokens]) ->
    {Fields, [rbrace | Rest]} = parse_selection_set_fields(Tokens, []),
    {Fields, Rest};
maybe_parse_selection_set(Tokens) ->
    {[], Tokens}.

skip_comma([comma | Rest]) -> Rest;
skip_comma(Tokens) -> Tokens.

skip_to(Token, [Token | Rest]) -> Rest;
skip_to(Token, [_ | Rest])     -> skip_to(Token, Rest);
skip_to(_, [])                 -> [].

%% ---------------------------------------------------------------------------
%% Internal: resolution
%% ---------------------------------------------------------------------------

-spec resolve_document(document()) -> map().
resolve_document(#{selection_set := Fields}) ->
    lists:foldl(fun(Field, Acc) ->
        #{name := Name} = Field,
        Value = resolve_root_field(Field),
        Acc#{Name => Value}
    end, #{}, Fields).

-spec resolve_root_field(selection()) -> term().
resolve_root_field(#{name := <<"party">>, arguments := Args, selection_set := SelSet}) ->
    Id = require_arg(Args, <<"id">>, <<"party">>),
    case cb_party:get_party(Id) of
        {ok, Party} -> apply_selection(party_to_map(Party), SelSet);
        {error, not_found} -> null
    end;

resolve_root_field(#{name := <<"account">>, arguments := Args, selection_set := SelSet}) ->
    Id = require_arg(Args, <<"id">>, <<"account">>),
    case cb_accounts:get_account(Id) of
        {ok, Acc} -> apply_selection(account_to_map(Acc), SelSet);
        {error, _} -> null
    end;

resolve_root_field(#{name := <<"parties">>, arguments := Args, selection_set := SelSet}) ->
    Page     = maps:get(<<"page">>,     Args, 1),
    PageSize = maps:get(<<"pageSize">>, Args, 20),
    case cb_party:list_parties(Page, PageSize) of
        {ok, #{items := Items, total := Total, page := P, page_size := PS}} ->
            Mapped = [apply_selection(party_to_map(I), subsel(SelSet, <<"items">>)) || I <- Items],
            apply_page_selection(#{
                <<"items">>    => Mapped,
                <<"total">>    => Total,
                <<"page">>     => P,
                <<"pageSize">> => PS
            }, SelSet);
        {error, _} ->
            #{<<"items">> => [], <<"total">> => 0, <<"page">> => 1, <<"pageSize">> => PageSize}
    end;

resolve_root_field(#{name := <<"accounts">>, arguments := Args, selection_set := SelSet}) ->
    case maps:get(<<"partyId">>, Args, undefined) of
        undefined ->
            Page     = maps:get(<<"page">>,     Args, 1),
            PageSize = maps:get(<<"pageSize">>, Args, 20),
            case cb_accounts:list_accounts(Page, PageSize) of
                {ok, #{items := Items, total := Total, page := P, page_size := PS}} ->
                    Mapped = [apply_selection(account_to_map(I), subsel(SelSet, <<"items">>)) || I <- Items],
                    apply_page_selection(#{
                        <<"items">>    => Mapped,
                        <<"total">>    => Total,
                        <<"page">>     => P,
                        <<"pageSize">> => PS
                    }, SelSet);
                {error, _} ->
                    #{<<"items">> => [], <<"total">> => 0, <<"page">> => 1, <<"pageSize">> => 20}
            end;
        PartyId ->
            Accs = cb_accounts:list_accounts_for_party(PartyId),
            Mapped = [apply_selection(account_to_map(A), subsel(SelSet, <<"items">>)) || A <- Accs],
            Total = length(Mapped),
            apply_page_selection(#{
                <<"items">>    => Mapped,
                <<"total">>    => Total,
                <<"page">>     => 1,
                <<"pageSize">> => Total
            }, SelSet)
    end;

resolve_root_field(#{name := Name}) ->
    throw({graphql_error, <<"Unknown field: ", Name/binary>>}).

%% Return the selection set of a named field within a parent selection set
-spec subsel([selection()], binary()) -> [selection()].
subsel([], _Name) -> [];
subsel([#{name := Name, selection_set := Sub} | _], Name) -> Sub;
subsel([_ | Rest], Name) -> subsel(Rest, Name).

%% Apply selection set to a page wrapper map (items + metadata)
-spec apply_page_selection(map(), [selection()]) -> map().
apply_page_selection(Page, []) -> Page;
apply_page_selection(Page, SelSet) ->
    maps:from_list(lists:filtermap(fun(#{name := Key, selection_set := Sub}) ->
        case maps:get(Key, Page, undefined) of
            undefined -> false;
            Items when Key =:= <<"items">>, Sub =/= [] ->
                %% items is already mapped; selection was already applied per-item
                {true, {Key, Items}};
            Val when Sub =/= [], is_map(Val) ->
                {true, {Key, apply_selection(Val, Sub)}};
            Val ->
                {true, {Key, Val}}
        end
    end, SelSet)).

%% Apply field selection set to a scalar map (keep only requested fields)
-spec apply_selection(map(), [selection()]) -> map().
apply_selection(Map, []) -> Map;
apply_selection(Map, SelSet) ->
    maps:from_list(lists:filtermap(fun(#{name := Key, selection_set := Sub}) ->
        case maps:get(Key, Map, undefined) of
            undefined ->
                false;
            Val when Sub =/= [], is_map(Val) ->
                {true, {Key, apply_selection(Val, Sub)}};
            Val ->
                {true, {Key, Val}}
        end
    end, SelSet)).

-spec require_arg(args(), binary(), binary()) -> binary().
require_arg(Args, Key, FieldName) ->
    case maps:get(Key, Args, undefined) of
        undefined ->
            throw({graphql_error, <<FieldName/binary, " requires '", Key/binary, "' argument">>});
        Val ->
            Val
    end.

-spec party_to_map(#party{}) -> map().
party_to_map(P) ->
    #{
        <<"id">>               => P#party.party_id,
        <<"fullName">>         => P#party.full_name,
        <<"email">>            => P#party.email,
        <<"status">>           => atom_to_binary(P#party.status, utf8),
        <<"kycStatus">>        => atom_to_binary(P#party.kyc_status, utf8),
        <<"onboardingStatus">> => atom_to_binary(P#party.onboarding_status, utf8),
        <<"createdAt">>        => P#party.created_at,
        <<"updatedAt">>        => P#party.updated_at
    }.

-spec account_to_map(#account{}) -> map().
account_to_map(A) ->
    #{
        <<"id">>        => A#account.account_id,
        <<"partyId">>   => A#account.party_id,
        <<"name">>      => A#account.name,
        <<"currency">>  => atom_to_binary(A#account.currency, utf8),
        <<"balance">>   => A#account.balance,
        <<"status">>    => atom_to_binary(A#account.status, utf8),
        <<"createdAt">> => A#account.created_at,
        <<"updatedAt">> => A#account.updated_at
    }.
