-module(otpbp_erlang).

-ifndef(HAVE_erlang__binary_to_integer_1).
-export([binary_to_integer/1]).
-endif.
-ifndef(HAVE_erlang__binary_to_integer_2).
-export([binary_to_integer/2]).
-endif.
-ifndef(HAVE_erlang__binary_to_float_1).
-export([binary_to_float/1]).
-endif.
-ifndef(HAVE_erlang__integer_to_binary_1).
-export([integer_to_binary/1]).
-endif.
-ifndef(HAVE_erlang__integer_to_binary_2).
-export([integer_to_binary/2]).
-endif.
-ifndef(HAVE_erlang__float_to_binary_1).
-export([float_to_binary/1]).
-endif.
-ifndef(HAVE_erlang__float_to_list_2).
-export([float_to_list/2]).
-endif.
-ifndef(HAVE_erlang__float_to_binary_2).
-export([float_to_binary/2]).
-endif.
-ifndef(HAVE_erlang__delete_element_2).
-export([delete_element/2]).
-endif.
-ifndef(HAVE_erlang__insert_element_3).
-export([insert_element/3]).
-endif.
-ifndef(HAVE_erlang__get_keys_0).
-export([get_keys/0]).
-endif.
-ifndef(HAVE_erlang__convert_time_unit_3).
-export([convert_time_unit/3]).
-endif.
-ifndef(HAVE_erlang__system_time_0).
-export([system_time/0]).
-endif.
-ifndef(HAVE_erlang__system_time_1).
-export([system_time/1]).
-endif.
-ifndef(HAVE_erlang__monotonic_time_0).
-export([monotonic_time/0]).
-endif.
-ifndef(HAVE_erlang__monotonic_time_1).
-export([monotonic_time/1]).
-endif.
-ifndef(HAVE_erlang__time_offset_0).
-export([time_offset/0]).
-endif.
-ifndef(HAVE_erlang__time_offset_1).
-export([time_offset/1]).
-endif.
-ifndef(HAVE_erlang__unique_integer_0).
-export([unique_integer/0]).
-endif.
-ifndef(HAVE_erlang__unique_integer_1).
-export([unique_integer/1]).
-endif.
-ifndef(HAVE_erlang__is_map_1).
-export([is_map/1]).
-endif.

-ifndef(HAVE_erlang__ceil_1).
-export([ceil/1]).
-endif.

-ifndef(HAVE_erlang__floor_1).
-export([floor/1]).
-endif.

-ifndef(HAVE_erlang__binary_to_integer_1).
binary_to_integer(Binary) -> list_to_integer(binary_to_list(Binary)).
-endif.

-ifndef(HAVE_erlang__binary_to_integer_2).
binary_to_integer(Binary, Base) -> list_to_integer(binary_to_list(Binary), Base).
-endif.

-ifndef(HAVE_erlang__binary_to_float_1).
binary_to_float(Binary) -> list_to_float(binary_to_list(Binary)).
-endif.

-ifndef(HAVE_erlang__integer_to_binary_1).
integer_to_binary(Integer) -> list_to_binary(integer_to_list(Integer)).
-endif.

-ifndef(HAVE_erlang__integer_to_binary_2).
integer_to_binary(Integer, Base) -> list_to_binary(integer_to_list(Integer, Base)).
-endif.

-ifndef(HAVE_erlang__float_to_binary_1).
float_to_binary(Float) -> list_to_binary(float_to_list(Float)).
-endif.

-ifndef(HAVE_erlang__float_to_binary_2).
-ifdef(HAVE_erlang__float_to_binary_1).
float_to_binary(Float, []) -> float_to_binary(Float);
float_to_binary(Float, Options) -> list_to_binary(float_to_list(Float, Options)).
-ifndef(NEED_erlang__float_to_list_2).
-define(NEED_erlang__float_to_list_2, true).
-endif.
-else.
float_to_binary(Float, Options) -> list_to_binary(float_to_list(Float, Options)).
-endif.
-endif.

-ifndef(HAVE_erlang__float_to_list_2).
-ifndef(NEED_erlang__float_to_list_2).
-define(NEED_erlang__float_to_list_2, true).
-endif.
-endif.

-ifdef(NEED_erlang__float_to_list_2).
float_to_list(Float, []) -> float_to_list(Float);
float_to_list(Float, Options) when is_float(Float), is_list(Options) ->
    case lists:foldl(fun(compact, {Format, Dec, _}) -> {Format, Dec, true};
                        ({decimals, D}, {_, _, Compact}) when is_integer(D), D >= 0, D =< 253 -> {decimals, D, Compact};
                        ({scientific, D}, {_, _, Compact}) when is_integer(D), D >= 0, D =< 249 ->
                         {scientific, D, Compact};
                        (O, _) -> error(badarg, [Float, O])
                     end, {none, 0, false}, Options) of
        {scientific, D, _} ->
            S = lists:flatten(io_lib:format("~.*e", [D + 1, Float])),
            case lists:reverse(S) of
                [C, Sign|M] when Sign =:= $+ orelse Sign =:= $- -> lists:reverse([C, $0, Sign|M]);
                _ -> S
            end;
        {decimals, D, C} ->
            S = lists:flatten(io_lib:format("~.*f", [D, Float])),
            if
                C -> string:strip(S, right, $0);
                true -> S
            end;
        {none, _, _} -> float_to_list(Float)
    end;
float_to_list(Float, O) -> error(badarg, [Float, O]).
-endif.

-ifndef(HAVE_erlang__delete_element_2).
delete_element(Index, Tuple) when is_integer(Index), Index > 0, Index =< tuple_size(Tuple) ->
    delete_element(Index, Tuple, [], tuple_size(Tuple));
delete_element(Index, Tuple) -> error(badarg, [Index, Tuple]).

delete_element(_, _, List, 0) -> list_to_tuple(List);
delete_element(Index, Tuple, List, Index) -> delete_element(Index, Tuple, List, Index - 1);
delete_element(Index, Tuple, List, I) -> delete_element(Index, Tuple, [element(I, Tuple)|List], I - 1).
-endif.

-ifndef(HAVE_erlang__insert_element_3).
insert_element(Index, Tuple, Term) when Index =:= tuple_size(Tuple) + 1 -> erlang:append_element(Tuple, Term);
insert_element(Index, Tuple, Term) when is_integer(Index), Index > 0, Index =< tuple_size(Tuple) ->
    insert_element(Index, Tuple, Term, [], tuple_size(Tuple));
insert_element(Index, Tuple, Term) -> error(badarg, [Index, Tuple, Term]).

insert_element(_, _, _, List, 0) -> list_to_tuple(List);
insert_element(Index, Tuple, Term, List, Index) ->
    insert_element(Index, Tuple, Term, [Term, element(Index, Tuple)|List], Index - 1);
insert_element(Index, Tuple, Term, List, I) -> insert_element(Index, Tuple, Term, [element(I, Tuple)|List], I - 1).
-endif.

-ifndef(HAVE_erlang__get_keys_0).
get_keys() -> proplists:get_keys(get()).
-endif.

-ifndef(HAVE_erlang__convert_time_unit_3).
convert_time_unit(Time, FromUnit, ToUnit) when is_integer(Time) ->
    FU = integer_time_unit(FromUnit),
    TU = integer_time_unit(ToUnit) * Time,
    if
        Time < 0 -> TU - FU + 1;
        true -> TU
    end div FU.

integer_time_unit(native) -> 1000000;
integer_time_unit(nano_seconds) -> 1000000000;
integer_time_unit(micro_seconds) -> 1000000;
integer_time_unit(milli_seconds) -> 1000;
integer_time_unit(seconds) -> 1;
integer_time_unit(I) when is_integer(I), I > 0 -> I;
integer_time_unit(BadRes) -> error(badarg, [BadRes]).
-endif.

-ifndef(HAVE_erlang__system_time_0).
system_time() ->
    {MS, S, US} = os:timestamp(),
    (MS * 1000000 + S) * 1000000 + US.
-endif.

-ifndef(HAVE_erlang__system_time_1).
system_time(nano_seconds) -> system_time() * 1000;
system_time(micro_seconds) -> system_time();
system_time(milli_seconds) -> system_time() div 1000;
system_time(seconds) ->
    {MS, S, _} = os:timestamp(),
    MS * 1000000 + S;
system_time(I) when is_integer(I), I > 0 -> system_time() * I div 1000000;
system_time(BadArg) -> error(badarg, [BadArg]).
-endif.

-ifndef(HAVE_erlang__monotonic_time_0).
monotonic_time() ->
    {MS, S, US} = now(),
    (MS * 1000000 + S) * 1000000 + US.
-endif.

-ifndef(HAVE_erlang__monotonic_time_1).
monotonic_time(nano_seconds) -> monotonic_time() * 1000;
monotonic_time(micro_seconds) -> monotonic_time();
monotonic_time(milli_seconds) -> monotonic_time() div 1000;
monotonic_time(seconds) ->
    {MS, S, _} = now(),
    MS * 1000000 + S;
monotonic_time(I) when is_integer(I), I > 0 -> monotonic_time() * I div 1000000;
monotonic_time(BadArg) -> error(badarg, [BadArg]).
-endif.

-ifndef(HAVE_erlang__time_offset_0).
time_offset() -> 0.
-endif.

-ifndef(HAVE_erlang__time_offset_1).
time_offset(nano_seconds) -> 0;
time_offset(micro_seconds) -> 0;
time_offset(milli_seconds) -> 0;
time_offset(seconds) -> 0;
time_offset(I) when is_integer(I), I > 0 -> 0;
time_offset(BadArg) -> error(badarg, [BadArg]).
-endif.

-ifndef(HAVE_erlang__unique_integer_0).
unique_integer() -> unique_integer([]).
-endif.

-ifndef(HAVE_erlang__unique_integer_1).
unique_integer([]) -> monotonic_time();
unique_integer([positive|O]) -> unique_integer(O);
unique_integer([monotonic|O]) -> unique_integer(O);
unique_integer(O) -> error(badarg, [O]).
-endif.

-ifndef(HAVE_erlang__is_map_1).
is_map(Map) -> is_record(Map, dict, tuple_size(dict:new())).
-endif.

-ifndef(HAVE_erlang__ceil_1).
-ifdef(HAVE_math__ceil_1).
ceil(X) -> round(math:ceil(X)).
-else.
ceil(X) -> round(X + 0.5).
-endif.
-endif.

-ifndef(HAVE_erlang__floor_1).
-ifdef(HAVE_math__floor_1).
floor(X) -> round(math:floor(X)).
-else.
floor(X) -> round(X - 0.5).
-endif.
-endif.
