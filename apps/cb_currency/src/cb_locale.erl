%% @doc Locale Packs: Date, Number, and Currency Formatting (P1-S3, TASK-035).
%%
%% Provides locale-aware formatting helpers for:
%%
%%   * Dates/datetimes (ISO 8601, regional long-form, short-form)
%%   * Numbers (thousands separator, decimal mark)
%%   * Currency amounts (symbol placement, minor-unit scaling)
%%
%% == Locale Identifiers ==
%%
%% Locales follow the IETF BCP 47 convention as Erlang binaries:
%%   <<"en-US">>  <<"en-GB">>  <<"de-DE">>  <<"ja-JP">>  <<"ar-SA">>
%%
%% == Usage ==
%%
%% ```
%% {ok, <<"$1,234.56">>} = cb_locale:format_currency(1234_56, 'USD', <<"en-US">>).
%% {ok, <<"1.234,56 €">>} = cb_locale:format_currency(1234_56, 'EUR', <<"de-DE">>).
%% {ok, <<"2024-07-04">>} = cb_locale:format_date(1720051200000, <<"en-US">>, iso8601).
%% ```
-module(cb_locale).

-include_lib("cb_ledger/include/cb_ledger.hrl").

-export([
    %% Currency formatting
    format_currency/3,
    format_currency/4,
    minor_units_for/1,

    %% Number formatting
    format_number/2,
    format_number/3,

    %% Date/time formatting
    format_date/3,
    format_datetime/3,

    %% Locale metadata
    locale_info/1,
    supported_locales/0,
    is_rtl/1
]).

-type format_style() :: iso8601 | long | short | numeric.
-type locale_id()    :: binary().

%%--------------------------------------------------------------------
%% Currency Formatting
%%--------------------------------------------------------------------

%% @doc Format a monetary amount in minor units for the given locale.
%%
%% `AmountMinor' — integer in minor units (cents, pence, …).
%% `Currency'    — ISO 4217 atom.
%% `Locale'      — IETF locale string, e.g. <<"en-US">>.
%%
%% Returns a formatted binary like <<"$1,234.56">> or <<"1.234,56 €">>.
-spec format_currency(amount(), currency(), locale_id()) ->
    {ok, binary()} | {error, unsupported_locale}.
format_currency(AmountMinor, Currency, Locale) ->
    format_currency(AmountMinor, Currency, Locale, #{}).

-spec format_currency(amount(), currency(), locale_id(), map()) ->
    {ok, binary()} | {error, unsupported_locale}.
format_currency(AmountMinor, Currency, Locale, _Opts) ->
    case locale_info(Locale) of
        {error, _} = Err -> Err;
        {ok, Info} ->
            Scale     = minor_units_for(Currency),
            Major     = AmountMinor div Scale,
            Minor     = AmountMinor rem Scale,
            DecMark   = maps:get(decimal_mark, Info),
            ThousSep  = maps:get(thousands_sep, Info),
            Symbol    = currency_symbol(Currency, Locale),
            Placement = maps:get(currency_placement, Info),
            MajorFmt  = format_integer_with_sep(Major, ThousSep),
            MinorStr  = format_minor(Minor, Scale),
            Amount    = <<MajorFmt/binary, DecMark/binary, MinorStr/binary>>,
            Result = case Placement of
                prefix -> <<Symbol/binary, Amount/binary>>;
                suffix -> <<Amount/binary, " ", Symbol/binary>>
            end,
            {ok, Result}
    end.

%% @doc Return the number of minor units for a currency.
%%
%% JPY has 0 decimal places (1 unit = 1 yen).
%% All others default to 2 decimal places.
-spec minor_units_for(currency()) -> pos_integer().
minor_units_for('JPY') -> 1;
minor_units_for(_)     -> 100.

%%--------------------------------------------------------------------
%% Number Formatting
%%--------------------------------------------------------------------

%% @doc Format an integer with locale-appropriate thousands separators.
-spec format_number(integer(), locale_id()) ->
    {ok, binary()} | {error, unsupported_locale}.
format_number(Number, Locale) ->
    format_number(Number, Locale, #{}).

-spec format_number(integer(), locale_id(), map()) ->
    {ok, binary()} | {error, unsupported_locale}.
format_number(Number, Locale, Opts) ->
    case locale_info(Locale) of
        {error, _} = Err -> Err;
        {ok, Info} ->
            ThousSep  = maps:get(thousands_sep, Info),
            DecMark   = maps:get(decimal_mark, Info),
            Decimals  = maps:get(decimals, Opts, 0),
            Scale     = trunc(math:pow(10, Decimals)),
            Major     = abs(Number) div Scale,
            Minor     = abs(Number) rem Scale,
            Sign      = if Number < 0 -> <<"-">>; true -> <<"">> end,
            MajorFmt  = format_integer_with_sep(Major, ThousSep),
            Result = if
                Decimals > 0 ->
                    MinorStr = format_minor(Minor, Scale),
                    <<Sign/binary, MajorFmt/binary, DecMark/binary, MinorStr/binary>>;
                true ->
                    <<Sign/binary, MajorFmt/binary>>
            end,
            {ok, Result}
    end.

%%--------------------------------------------------------------------
%% Date/Time Formatting
%%--------------------------------------------------------------------

%% @doc Format a millisecond timestamp as a date string.
%%
%% `Style' — `iso8601' | `long' | `short' | `numeric'.
-spec format_date(timestamp_ms(), locale_id(), format_style()) ->
    {ok, binary()} | {error, unsupported_locale}.
format_date(TimestampMs, Locale, Style) ->
    case locale_info(Locale) of
        {error, _} = Err -> Err;
        {ok, Info} ->
            Secs = TimestampMs div 1000,
            {{Y, M, D}, _} = calendar:gregorian_seconds_to_datetime(
                               Secs + calendar:datetime_to_gregorian_seconds({{1970,1,1},{0,0,0}})),
            Formatted = apply_date_format(Y, M, D, Style, Info, Locale),
            {ok, Formatted}
    end.

%% @doc Format a millisecond timestamp as a datetime string.
-spec format_datetime(timestamp_ms(), locale_id(), format_style()) ->
    {ok, binary()} | {error, unsupported_locale}.
format_datetime(TimestampMs, Locale, Style) ->
    case locale_info(Locale) of
        {error, _} = Err -> Err;
        {ok, Info} ->
            Secs = TimestampMs div 1000,
            {{Y, M, D}, {H, Min, S}} = calendar:gregorian_seconds_to_datetime(
                                         Secs + calendar:datetime_to_gregorian_seconds({{1970,1,1},{0,0,0}})),
            DatePart = apply_date_format(Y, M, D, Style, Info, Locale),
            TimePart = iolist_to_binary(io_lib:format("~2..0B:~2..0B:~2..0B", [H, Min, S])),
            {ok, <<DatePart/binary, "T", TimePart/binary>>}
    end.

%%--------------------------------------------------------------------
%% Locale Metadata
%%--------------------------------------------------------------------

%% @doc Return locale descriptor map or {error, unsupported_locale}.
-spec locale_info(locale_id()) ->
    {ok, map()} | {error, unsupported_locale}.
locale_info(<<"en-US">>) ->
    {ok, #{decimal_mark => <<".">>, thousands_sep => <<",">>,
           currency_placement => prefix, date_order => mdy,
           month_names => en_month_names(), rtl => false}};
locale_info(<<"en-GB">>) ->
    {ok, #{decimal_mark => <<".">>, thousands_sep => <<",">>,
           currency_placement => prefix, date_order => dmy,
           month_names => en_month_names(), rtl => false}};
locale_info(<<"en-AU">>) ->
    {ok, #{decimal_mark => <<".">>, thousands_sep => <<",">>,
           currency_placement => prefix, date_order => dmy,
           month_names => en_month_names(), rtl => false}};
locale_info(<<"de-DE">>) ->
    {ok, #{decimal_mark => <<",">>, thousands_sep => <<".">>,
           currency_placement => suffix, date_order => dmy,
           month_names => de_month_names(), rtl => false}};
locale_info(<<"fr-FR">>) ->
    {ok, #{decimal_mark => <<",">>, thousands_sep => <<" ">>,
           currency_placement => suffix, date_order => dmy,
           month_names => fr_month_names(), rtl => false}};
locale_info(<<"ja-JP">>) ->
    {ok, #{decimal_mark => <<".">>, thousands_sep => <<",">>,
           currency_placement => prefix, date_order => ymd,
           month_names => en_month_names(), rtl => false}};
locale_info(<<"zh-CN">>) ->
    {ok, #{decimal_mark => <<".">>, thousands_sep => <<",">>,
           currency_placement => prefix, date_order => ymd,
           month_names => en_month_names(), rtl => false}};
locale_info(<<"ar-SA">>) ->
    {ok, #{decimal_mark => <<".">>, thousands_sep => <<",">>,
           currency_placement => suffix, date_order => dmy,
           month_names => en_month_names(), rtl => true}};
locale_info(<<"ar-AE">>) ->
    {ok, #{decimal_mark => <<".">>, thousands_sep => <<",">>,
           currency_placement => suffix, date_order => dmy,
           month_names => en_month_names(), rtl => true}};
locale_info(<<"he-IL">>) ->
    {ok, #{decimal_mark => <<".">>, thousands_sep => <<",">>,
           currency_placement => suffix, date_order => dmy,
           month_names => en_month_names(), rtl => true}};
locale_info(<<"sg-SG">>) ->
    %% Singapore English
    {ok, #{decimal_mark => <<".">>, thousands_sep => <<",">>,
           currency_placement => prefix, date_order => dmy,
           month_names => en_month_names(), rtl => false}};
locale_info(_) ->
    {error, unsupported_locale}.

%% @doc Return list of supported locale identifiers.
-spec supported_locales() -> [locale_id()].
supported_locales() ->
    [<<"en-US">>, <<"en-GB">>, <<"en-AU">>, <<"de-DE">>, <<"fr-FR">>,
     <<"ja-JP">>, <<"zh-CN">>, <<"ar-SA">>, <<"ar-AE">>, <<"he-IL">>,
     <<"sg-SG">>].

%% @doc Return true if the locale uses right-to-left text direction.
-spec is_rtl(locale_id()) -> boolean().
is_rtl(Locale) ->
    case locale_info(Locale) of
        {ok, Info} -> maps:get(rtl, Info, false);
        {error, _} -> false
    end.

%%--------------------------------------------------------------------
%% Internal helpers
%%--------------------------------------------------------------------

format_integer_with_sep(0, _Sep) -> <<"0">>;
format_integer_with_sep(N, Sep) when N > 0 ->
    Digits = integer_to_binary(N),
    insert_thousands_sep(Digits, Sep).

insert_thousands_sep(Digits, Sep) ->
    Len = byte_size(Digits),
    Rem = Len rem 3,
    case Rem of
        0 ->
            Parts = [binary:part(Digits, I*3, 3) || I <- lists:seq(0, (Len div 3) - 1)],
            join_with(Parts, Sep);
        _ ->
            Head = binary:part(Digits, 0, Rem),
            Tail = [binary:part(Digits, Rem + I*3, 3) || I <- lists:seq(0, (Len - Rem) div 3 - 1)],
            join_with([Head | Tail], Sep)
    end.

join_with([], _Sep)     -> <<"">>;
join_with([H], _Sep)    -> H;
join_with([H | T], Sep) -> <<H/binary, Sep/binary, (join_with(T, Sep))/binary>>.

format_minor(Minor, Scale) ->
    Decimals = trunc(math:log10(Scale)),
    Fmt = "~" ++ integer_to_list(Decimals) ++ "..0B",
    iolist_to_binary(io_lib:format(Fmt, [Minor])).

apply_date_format(Y, M, D, iso8601, _Info, _Locale) ->
    iolist_to_binary(io_lib:format("~4..0B-~2..0B-~2..0B", [Y, M, D]));
apply_date_format(Y, M, D, numeric, Info, _Locale) ->
    Order = maps:get(date_order, Info, mdy),
    Sep = <<"/">>,
    MB = integer_to_binary(M),
    DB = integer_to_binary(D),
    YB = integer_to_binary(Y),
    case Order of
        mdy -> <<MB/binary, Sep/binary, DB/binary, Sep/binary, YB/binary>>;
        dmy -> <<DB/binary, Sep/binary, MB/binary, Sep/binary, YB/binary>>;
        ymd -> <<YB/binary, Sep/binary, MB/binary, Sep/binary, DB/binary>>
    end;
apply_date_format(Y, M, D, long, Info, _Locale) ->
    MonthNames = maps:get(month_names, Info),
    MonthName  = lists:nth(M, MonthNames),
    Order = maps:get(date_order, Info, mdy),
    DB = integer_to_binary(D),
    YB = integer_to_binary(Y),
    MB = integer_to_binary(M),
    case Order of
        mdy -> <<MonthName/binary, " ", DB/binary, ", ", YB/binary>>;
        dmy -> <<DB/binary, " ", MonthName/binary, " ", YB/binary>>;
        ymd -> <<YB/binary, "年", MB/binary, "月", DB/binary, "日">>
    end;
apply_date_format(Y, M, D, short, Info, Locale) ->
    apply_date_format(Y, M, D, numeric, Info, Locale).

currency_symbol('USD', Locale) when Locale =:= <<"en-US">> -> <<"$">>;
currency_symbol('USD', _)     -> <<"USD">>;
currency_symbol('EUR', _)     -> <<"€">>;
currency_symbol('GBP', _)     -> <<"£">>;
currency_symbol('JPY', _)     -> <<"¥">>;
currency_symbol('CHF', _)     -> <<"CHF">>;
currency_symbol('AUD', _)     -> <<"A$">>;
currency_symbol('CAD', _)     -> <<"C$">>;
currency_symbol('SGD', _)     -> <<"S$">>;
currency_symbol('HKD', _)     -> <<"HK$">>;
currency_symbol('NZD', _)     -> <<"NZ$">>.

en_month_names() ->
    [<<"January">>,<<"February">>,<<"March">>,<<"April">>,<<"May">>,<<"June">>,
     <<"July">>,<<"August">>,<<"September">>,<<"October">>,<<"November">>,<<"December">>].

de_month_names() ->
    [<<"Januar">>,<<"Februar">>,<<"März">>,<<"April">>,<<"Mai">>,<<"Juni">>,
     <<"Juli">>,<<"August">>,<<"September">>,<<"Oktober">>,<<"November">>,<<"Dezember">>].

fr_month_names() ->
    [<<"janvier">>,<<"février">>,<<"mars">>,<<"avril">>,<<"mai">>,<<"juin">>,
     <<"juillet">>,<<"août">>,<<"septembre">>,<<"octobre">>,<<"novembre">>,<<"décembre">>].
