%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 2015. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%
%% %CopyrightEnd%
%%
%% =====================================================================
%% Multiple PRNG module for Erlang/OTP
%% Copyright (c) 2015 Kenji Rikitake
%% =====================================================================

-module(otpbp_rand).

-ifndef(HAVE_rand__seed_1).
-compile([{parse_transform, otpbp_pt}]).

-export([seed_s/1, seed_s/2, seed/1, seed/2,
	 export_seed/0, export_seed_s/1,
         uniform/0, uniform/1, uniform_s/1, uniform_s/2,
	 normal/0, normal_s/1
	]).

-compile({inline, [exs64_next/1, exsplus_next/1,
		   exs1024_next/1, exs1024_calc/2,
		   get_52/1, normal_kiwi/1]}).

-define(DEFAULT_ALG_HANDLER, exsplus).
-define(SEED_DICT, rand_seed).

%% =====================================================================
%% Types
%% =====================================================================

%% This depends on the algorithm handler function
-type alg_seed() :: exs64_state() | exsplus_state() | exs1024_state().
%% This is the algorithm handler function within this module
-ifndef(HAVE_erlang__is_map_1).
-record(alg_handler, {type = none :: alg(),
		      max = none :: integer(),
		      next = none :: fun(),
		      uniform = none :: fun(),
		      uniform_n = none :: fun()}).
-type alg_handler() :: #alg_handler{}.
-else.
-type alg_handler() :: #{type      => alg(),
			 max       => integer(),
			 next      => fun(),
			 uniform   => fun(),
			 uniform_n => fun()}.
-endif.

%% Internal state
-opaque state() :: {alg_handler(), alg_seed()}.
-type alg() :: exs64 | exsplus | exs1024.
-opaque export_state() :: {alg(), alg_seed()}.
-export_type([alg/0, state/0, export_state/0]).

%% =====================================================================
%% API
%% =====================================================================

%% Return algorithm and seed so that RNG state can be recreated with seed/1
-spec export_seed() -> undefined | export_state().
-ifndef(HAVE_erlang__is_map_1).
export_seed() ->
    case seed_get() of
	{#alg_handler{type=Alg}, Seed} when Alg =/= none -> {Alg, Seed};
	_ -> undefined
    end.
-else.
export_seed() ->
    case seed_get() of
	{#{type:=Alg}, Seed} -> {Alg, Seed};
	_ -> undefined
    end.
-endif.

-spec export_seed_s(state()) -> export_state().
-ifndef(HAVE_erlang__is_map_1).
export_seed_s({#alg_handler{type=Alg}, Seed}) when Alg =/= none -> {Alg, Seed}.
-else.
export_seed_s({#{type:=Alg}, Seed}) -> {Alg, Seed}.
-endif.

%% seed(Alg) seeds RNG with runtime dependent values
%% and return the NEW state

%% seed({Alg,Seed}) setup RNG with a previously exported seed
%% and return the NEW state

-spec seed(AlgOrExpState::alg() | export_state()) -> state().
seed(Alg) ->
    R = seed_s(Alg),
    _ = seed_put(R),
    R.

-spec seed_s(AlgOrExpState::alg() | export_state()) -> state().
-ifdef(HAVE_erlang__unique_integer_0).
seed_s(Alg) when is_atom(Alg) ->
    seed_s(Alg, {erlang:phash2([{node(),self()}]),
		 erlang:system_time(),
		 erlang:unique_integer()});
seed_s({Alg0, Seed}) ->
    {Alg,_SeedFun} = mk_alg(Alg0),
    {Alg, Seed}.
-else.
seed_s(Alg) when is_atom(Alg) ->
    ST = erlang:system_time(),
    seed_s(Alg, {erlang:phash2([{node(), self()}]), ST div 1000, ST rem 1000});
seed_s({Alg0, Seed}) ->
    {Alg,_SeedFun} = mk_alg(Alg0),
    {Alg, Seed}.
-endif.

%% seed/2: seeds RNG with the algorithm and given values
%% and returns the NEW state.

-spec seed(Alg :: alg(), {integer(), integer(), integer()}) -> state().
seed(Alg0, S0) ->
    State = seed_s(Alg0, S0),
    _ = seed_put(State),
    State.

-spec seed_s(Alg :: alg(), {integer(), integer(), integer()}) -> state().
seed_s(Alg0, S0 = {_, _, _}) ->
    {Alg, Seed} = mk_alg(Alg0),
    AS = Seed(S0),
    {Alg, AS}.

%%% uniform/0, uniform/1, uniform_s/1, uniform_s/2 are all
%%% uniformly distributed random numbers.

%% uniform/0: returns a random float X where 0.0 < X < 1.0,
%% updating the state in the process dictionary.

-spec uniform() -> X::float().
uniform() ->
    {X, Seed} = uniform_s(seed_get()),
    _ = seed_put(Seed),
    X.

%% uniform/1: given an integer N >= 1,
%% uniform/1 returns a random integer X where 1 =< X =< N,
%% updating the state in the process dictionary.

-spec uniform(N :: pos_integer()) -> X::pos_integer().
uniform(N) ->
    {X, Seed} = uniform_s(N, seed_get()),
    _ = seed_put(Seed),
    X.

%% uniform_s/1: given a state, uniform_s/1
%% returns a random float X where 0.0 < X < 1.0,
%% and a new state.

-spec uniform_s(state()) -> {X::float(), NewS :: state()}.
-ifndef(HAVE_erlang__is_map_1).
uniform_s(State = {#alg_handler{uniform=Uniform}, _}) when Uniform =/= none ->
    Uniform(State).
-else.
uniform_s(State = {#{uniform:=Uniform}, _}) ->
    Uniform(State).
-endif.

%% uniform_s/2: given an integer N >= 1 and a state, uniform_s/2
%% uniform_s/2 returns a random integer X where 1 =< X =< N,
%% and a new state.

-spec uniform_s(N::pos_integer(), state()) -> {X::pos_integer(), NewS::state()}.
-ifndef(HAVE_erlang__is_map_1).
uniform_s(N, State = {#alg_handler{uniform_n=Uniform, max=Max}, _})
  when Uniform =/= none, Max =/= none, 0 < N, N =< Max ->
    Uniform(N, State);
uniform_s(N, State0 = {#alg_handler{uniform=Uniform}, _})
  when Uniform =/= none, is_integer(N), 0 < N ->
    {F, State} = Uniform(State0),
    {trunc(F * N) + 1, State}.
-else.
uniform_s(N, State = {#{uniform_n:=Uniform, max:=Max}, _})
  when 0 < N, N =< Max ->
    Uniform(N, State);
uniform_s(N, State0 = {#{uniform:=Uniform}, _})
  when is_integer(N), 0 < N ->
    {F, State} = Uniform(State0),
    {trunc(F * N) + 1, State}.
-endif.

%% normal/0: returns a random float with standard normal distribution
%% updating the state in the process dictionary.

-spec normal() -> float().
normal() ->
    {X, Seed} = normal_s(seed_get()),
    _ = seed_put(Seed),
    X.

%% normal_s/1: returns a random float with standard normal distribution
%% The Ziggurat Method for generating random variables - Marsaglia and Tsang
%% Paper and reference code: http://www.jstatsoft.org/v05/i08/

-spec normal_s(state()) -> {float(), NewS :: state()}.
normal_s(State0) ->
    {Sign, R, State} = get_52(State0),
    Idx = R band 16#FF,
    Idx1 = Idx+1,
    {Ki, Wi} = normal_kiwi(Idx1),
    X = R * Wi,
    case R < Ki of
	%% Fast path 95% of the time
	true when Sign =:= 0 -> {X, State};
	true -> {-X, State};
	%% Slow path
	false when Sign =:= 0 -> normal_s(Idx, Sign, X, State);
	false -> normal_s(Idx, Sign, -X, State)
    end.

%% =====================================================================
%% Internal functions

-define(UINT21MASK, 16#00000000001fffff).
-define(UINT32MASK, 16#00000000ffffffff).
-define(UINT33MASK, 16#00000001ffffffff).
-define(UINT39MASK, 16#0000007fffffffff).
-define(UINT58MASK, 16#03ffffffffffffff).
-define(UINT64MASK, 16#ffffffffffffffff).

-type uint64() :: 0..16#ffffffffffffffff.
-type uint58() :: 0..16#03ffffffffffffff.

-spec seed_put(state()) -> undefined | state().
seed_put(Seed) ->
    put(?SEED_DICT, Seed).

seed_get() ->
    case get(?SEED_DICT) of
        undefined -> seed(?DEFAULT_ALG_HANDLER);
        Old -> Old  % no type checking here
    end.

%% Setup alg record
-ifndef(HAVE_erlang__is_map_1).
mk_alg(exs64) ->
    {#alg_handler{type=exs64, max=?UINT64MASK, next=fun exs64_next/1,
       uniform=fun exs64_uniform/1, uniform_n=fun exs64_uniform/2},
     fun exs64_seed/1};
mk_alg(exsplus) ->
    {#alg_handler{type=exsplus, max=?UINT58MASK, next=fun exsplus_next/1,
       uniform=fun exsplus_uniform/1, uniform_n=fun exsplus_uniform/2},
     fun exsplus_seed/1};
mk_alg(exs1024) ->
    {#alg_handler{type=exs1024, max=?UINT64MASK, next=fun exs1024_next/1,
       uniform=fun exs1024_uniform/1, uniform_n=fun exs1024_uniform/2},
     fun exs1024_seed/1}.
-else.
mk_alg(exs64) ->
    {#{type=>exs64, max=>?UINT64MASK, next=>fun exs64_next/1,
       uniform=>fun exs64_uniform/1, uniform_n=>fun exs64_uniform/2},
     fun exs64_seed/1};
mk_alg(exsplus) ->
    {#{type=>exsplus, max=>?UINT58MASK, next=>fun exsplus_next/1,
       uniform=>fun exsplus_uniform/1, uniform_n=>fun exsplus_uniform/2},
     fun exsplus_seed/1};
mk_alg(exs1024) ->
    {#{type=>exs1024, max=>?UINT64MASK, next=>fun exs1024_next/1,
       uniform=>fun exs1024_uniform/1, uniform_n=>fun exs1024_uniform/2},
     fun exs1024_seed/1}.
-endif.

%% =====================================================================
%% exs64 PRNG: Xorshift64*
%% Algorithm by Sebastiano Vigna
%% Reference URL: http://xorshift.di.unimi.it/
%% =====================================================================

-type exs64_state() :: uint64().

exs64_seed({A1, A2, A3}) ->
    {V1, _} = exs64_next(((A1 band ?UINT32MASK) * 4294967197 + 1)),
    {V2, _} = exs64_next(((A2 band ?UINT32MASK) * 4294967231 + 1)),
    {V3, _} = exs64_next(((A3 band ?UINT32MASK) * 4294967279 + 1)),
    ((V1 * V2 * V3) rem (?UINT64MASK - 1)) + 1.

%% Advance xorshift64* state for one step and generate 64bit unsigned integer
-spec exs64_next(exs64_state()) -> {uint64(), exs64_state()}.
exs64_next(R) ->
    R1 = R bxor (R bsr 12),
    R2 = R1 bxor ((R1 band ?UINT39MASK) bsl 25),
    R3 = R2 bxor (R2 bsr 27),
    {(R3 * 2685821657736338717) band ?UINT64MASK, R3}.

exs64_uniform({Alg, R0}) ->
    {V, R1} = exs64_next(R0),
    {V / 18446744073709551616, {Alg, R1}}.

exs64_uniform(Max, {Alg, R}) ->
    {V, R1} = exs64_next(R),
    {(V rem Max) + 1, {Alg, R1}}.

%% =====================================================================
%% exsplus PRNG: Xorshift116+
%% Algorithm by Sebastiano Vigna
%% Reference URL: http://xorshift.di.unimi.it/
%% 58 bits fits into an immediate on 64bits erlang and is thus much faster.
%% Modification of the original Xorshift128+ algorithm to 116
%% by Sebastiano Vigna, a lot of thanks for his help and work.
%% =====================================================================
-type exsplus_state() :: nonempty_improper_list(uint58(), uint58()).

exsplus_seed({A1, A2, A3}) ->
    {_, R1} = exsplus_next([(((A1 * 4294967197) + 1) band ?UINT58MASK)|
			    (((A2 * 4294967231) + 1) band ?UINT58MASK)]),
    {_, R2} = exsplus_next([(((A3 * 4294967279) + 1) band ?UINT58MASK)|
			    tl(R1)]),
    R2.

%% Advance xorshift116+ state for one step and generate 58bit unsigned integer
-spec exsplus_next(exsplus_state()) -> {uint58(), exsplus_state()}.
exsplus_next([S1|S0]) ->
    %% Note: members s0 and s1 are swapped here
    S11 = (S1 bxor (S1 bsl 24)) band ?UINT58MASK,
    S12 = S11 bxor S0 bxor (S11 bsr 11) bxor (S0 bsr 41),
    {(S0 + S12) band ?UINT58MASK, [S0|S12]}.

exsplus_uniform({Alg, R0}) ->
    {I, R1} = exsplus_next(R0),
    {I / (?UINT58MASK+1), {Alg, R1}}.

exsplus_uniform(Max, {Alg, R}) ->
    {V, R1} = exsplus_next(R),
    {(V rem Max) + 1, {Alg, R1}}.

%% =====================================================================
%% exs1024 PRNG: Xorshift1024*
%% Algorithm by Sebastiano Vigna
%% Reference URL: http://xorshift.di.unimi.it/
%% =====================================================================

-type exs1024_state() :: {list(uint64()), list(uint64())}.

exs1024_seed({A1, A2, A3}) ->
    B1 = (((A1 band ?UINT21MASK) + 1) * 2097131) band ?UINT21MASK,
    B2 = (((A2 band ?UINT21MASK) + 1) * 2097133) band ?UINT21MASK,
    B3 = (((A3 band ?UINT21MASK) + 1) * 2097143) band ?UINT21MASK,
    {exs1024_gen1024((B1 bsl 43) bor (B2 bsl 22) bor (B3 bsl 1) bor 1),
     []}.

%% Generate a list of 16 64-bit element list
%% of the xorshift64* random sequence
%% from a given 64-bit seed.
%% Note: dependent on exs64_next/1
-spec exs1024_gen1024(uint64()) -> list(uint64()).
exs1024_gen1024(R) ->
    exs1024_gen1024(16, R, []).

exs1024_gen1024(0, _, L) ->
    L;
exs1024_gen1024(N, R, L) ->
    {X, R2} = exs64_next(R),
    exs1024_gen1024(N - 1, R2, [X|L]).

%% Calculation of xorshift1024*.
%% exs1024_calc(S0, S1) -> {X, NS1}.
%% X: random number output
-spec exs1024_calc(uint64(), uint64()) -> {uint64(), uint64()}.
exs1024_calc(S0, S1) ->
    S11 = S1 bxor ((S1 band ?UINT33MASK) bsl 31),
    S12 = S11 bxor (S11 bsr 11),
    S01 = S0 bxor (S0 bsr 30),
    NS1 = S01 bxor S12,
    {(NS1 * 1181783497276652981) band ?UINT64MASK, NS1}.

%% Advance xorshift1024* state for one step and generate 64bit unsigned integer
-spec exs1024_next(exs1024_state()) -> {uint64(), exs1024_state()}.
exs1024_next({[S0,S1|L3], RL}) ->
    {X, NS1} = exs1024_calc(S0, S1),
    {X, {[NS1|L3], [S0|RL]}};
exs1024_next({[H], RL}) ->
    NL = [H|lists:reverse(RL)],
    exs1024_next({NL, []}).

exs1024_uniform({Alg, R0}) ->
    {V, R1} = exs1024_next(R0),
    {V / 18446744073709551616, {Alg, R1}}.

exs1024_uniform(Max, {Alg, R}) ->
    {V, R1} = exs1024_next(R),
    {(V rem Max) + 1, {Alg, R1}}.

%% =====================================================================
%% Ziggurat cont
%% =====================================================================
-define(NOR_R, 3.6541528853610087963519472518).
-define(NOR_INV_R, 1/?NOR_R).

%% return a {sign, Random51bits, State}
-ifndef(HAVE_erlang__is_map_1).
get_52({Alg=#alg_handler{next=Next}, S0}) when Next =/= none ->
    {Int,S1} = Next(S0),
    {((1 bsl 51) band Int), Int band ((1 bsl 51)-1), {Alg, S1}}.
-else.
get_52({Alg=#{next:=Next}, S0}) ->
    {Int,S1} = Next(S0),
    {((1 bsl 51) band Int), Int band ((1 bsl 51)-1), {Alg, S1}}.
-endif.

%% Slow path
normal_s(0, Sign, X0, State0) ->
    {U0, S1} = uniform_s(State0),
    X = -?NOR_INV_R*math:log(U0),
    {U1, S2} = uniform_s(S1),
    Y = -math:log(U1),
    case Y+Y > X*X of
	false ->
	    normal_s(0, Sign, X0, S2);
	true when Sign =:= 0 ->
	    {?NOR_R + X, S2};
	true ->
	    {-?NOR_R - X, S2}
    end;
normal_s(Idx, _Sign, X, State0) ->
    Fi2 = normal_fi(Idx+1),
    {U0, S1} = uniform_s(State0),
    case ((normal_fi(Idx) - Fi2)*U0 + Fi2) < math:exp(-0.5*X*X) of
	true ->  {X, S1};
	false -> normal_s(S1)
    end.

%% Tables for generating normal_s
%% ki is zipped with wi (slightly faster)
normal_kiwi(Indx) ->
    element(Indx,
	{{2104047571236786,1.736725412160263e-15}, {0,9.558660351455634e-17},
	 {1693657211986787,1.2708704834810623e-16},{1919380038271141,1.4909740962495474e-16},
	 {2015384402196343,1.6658733631586268e-16},{2068365869448128,1.8136120810119029e-16},
	 {2101878624052573,1.9429720153135588e-16},{2124958784102998,2.0589500628482093e-16},
	 {2141808670795147,2.1646860576895422e-16},{2154644611568301,2.2622940392218116e-16},
	 {2164744887587275,2.353271891404589e-16},{2172897953696594,2.438723455742877e-16},
	 {2179616279372365,2.5194879829274225e-16},{2185247251868649,2.5962199772528103e-16},
	 {2190034623107822,2.6694407473648285e-16},{2194154434521197,2.7395729685142446e-16},
	 {2197736978774660,2.8069646002484804e-16},{2200880740891961,2.871905890411393e-16},
	 {2203661538010620,2.9346417484728883e-16},{2206138681109102,2.9953809336782113e-16},
	 {2208359231806599,3.054303000719244e-16},{2210361007258210,3.111563633892157e-16},
	 {2212174742388539,3.1672988018581815e-16},{2213825672704646,3.2216280350549905e-16},
	 {2215334711002614,3.274657040793975e-16},{2216719334487595,3.326479811684171e-16},
	 {2217994262139172,3.377180341735323e-16},{2219171977965032,3.4268340353119356e-16},
	 {2220263139538712,3.475508873172976e-16},{2221276900117330,3.523266384600203e-16},
	 {2222221164932930,3.5701624633953494e-16},{2223102796829069,3.616248057159834e-16},
	 {2223927782546658,3.661569752965354e-16},{2224701368170060,3.7061702777236077e-16},
	 {2225428170204312,3.75008892787478e-16},{2226112267248242,3.7933619401549554e-16},
	 {2226757276105256,3.836022812967728e-16},{2227366415328399,3.8781025861250247e-16},
	 {2227942558554684,3.919630085325768e-16},{2228488279492521,3.9606321366256378e-16},
	 {2229005890047222,4.001133755254669e-16},{2229497472775193,4.041158312414333e-16},
	 {2229964908627060,4.080727683096045e-16},{2230409900758597,4.119862377480744e-16},
	 {2230833995044585,4.1585816580828064e-16},{2231238597816133,4.1969036444740733e-16},
	 {2231624991250191,4.234845407152071e-16},{2231994346765928,4.272423051889976e-16},
	 {2232347736722750,4.309651795716294e-16},{2232686144665934,4.346546035512876e-16},
	 {2233010474325959,4.383119410085457e-16},{2233321557544881,4.4193848564470665e-16},
	 {2233620161276071,4.455354660957914e-16},{2233906993781271,4.491040505882875e-16},
	 {2234182710130335,4.52645351185714e-16},{2234447917093496,4.561604276690038e-16},
	 {2234703177503020,4.596502910884941e-16},{2234949014150181,4.631159070208165e-16},
	 {2235185913274316,4.665581985600875e-16},{2235414327692884,4.699780490694195e-16},
	 {2235634679614920,4.733763047158324e-16},{2235847363174595,4.767537768090853e-16},
	 {2236052746716837,4.8011124396270155e-16},{2236251174862869,4.834494540935008e-16},
	 {2236442970379967,4.867691262742209e-16},{2236628435876762,4.900709524522994e-16},
	 {2236807855342765,4.933555990465414e-16},{2236981495548562,4.966237084322178e-16},
	 {2237149607321147,4.998759003240909e-16},{2237312426707209,5.031127730659319e-16},
	 {2237470176035652,5.0633490483427195e-16},{2237623064889403,5.095428547633892e-16},
	 {2237771290995388,5.127371639978797e-16},{2237915041040597,5.159183566785736e-16},
	 {2238054491421305,5.190869408670343e-16},{2238189808931712,5.222434094134042e-16},
	 {2238321151397660,5.253882407719454e-16},{2238448668260432,5.285218997682382e-16},
	 {2238572501115169,5.316448383216618e-16},{2238692784207942,5.34757496126473e-16},
	 {2238809644895133,5.378603012945235e-16},{2238923204068402,5.409536709623993e-16},
	 {2239033576548190,5.440380118655467e-16},{2239140871448443,5.471137208817361e-16},
	 {2239245192514958,5.501811855460336e-16},{2239346638439541,5.532407845392784e-16},
	 {2239445303151952,5.56292888151909e-16},{2239541276091442,5.593378587248462e-16},
	 {2239634642459498,5.623760510690043e-16},{2239725483455293,5.65407812864896e-16},
	 {2239813876495186,5.684334850436814e-16},{2239899895417494,5.714534021509204e-16},
	 {2239983610673676,5.744678926941961e-16},{2240065089506935,5.774772794756965e-16},
	 {2240144396119183,5.804818799107686e-16},{2240221591827230,5.834820063333892e-16},
	 {2240296735208969,5.864779662894365e-16},{2240369882240293,5.894700628185872e-16},
	 {2240441086423386,5.924585947256134e-16},{2240510398907004,5.95443856841806e-16},
	 {2240577868599305,5.984261402772028e-16},{2240643542273726,6.014057326642664e-16},
	 {2240707464668391,6.043829183936125e-16},{2240769678579486,6.073579788423606e-16},
	 {2240830224948980,6.103311925956439e-16},{2240889142947082,6.133028356617911e-16},
	 {2240946470049769,6.162731816816596e-16},{2241002242111691,6.192425021325847e-16},
	 {2241056493434746,6.222110665273788e-16},{2241109256832602,6.251791426088e-16},
	 {2241160563691400,6.281469965398895e-16},{2241210444026879,6.311148930905604e-16},
	 {2241258926538122,6.34083095820806e-16},{2241306038658137,6.370518672608815e-16},
	 {2241351806601435,6.400214690888025e-16},{2241396255408788,6.429921623054896e-16},
	 {2241439408989313,6.459642074078832e-16},{2241481290160038,6.489378645603397e-16},
	 {2241521920683062,6.519133937646159e-16},{2241561321300462,6.548910550287415e-16},
	 {2241599511767028,6.578711085350741e-16},{2241636510880960,6.608538148078259e-16},
	 {2241672336512612,6.638394348803506e-16},{2241707005631362,6.668282304624746e-16},
	 {2241740534330713,6.698204641081558e-16},{2241772937851689,6.728163993837531e-16},
	 {2241804230604585,6.758163010371901e-16},{2241834426189161,6.78820435168298e-16},
	 {2241863537413311,6.818290694006254e-16},{2241891576310281,6.848424730550038e-16},
	 {2241918554154466,6.878609173251664e-16},{2241944481475843,6.908846754557169e-16},
	 {2241969368073071,6.939140229227569e-16},{2241993223025298,6.969492376174829e-16},
	 {2242016054702685,6.999906000330764e-16},{2242037870775710,7.030383934552151e-16},
	 {2242058678223225,7.060929041565482e-16},{2242078483339331,7.091544215954873e-16},
	 {2242097291739040,7.122232386196779e-16},{2242115108362774,7.152996516745303e-16},
	 {2242131937479672,7.183839610172063e-16},{2242147782689725,7.214764709364707e-16},
	 {2242162646924736,7.245774899788387e-16},{2242176532448092,7.276873311814693e-16},
	 {2242189440853337,7.308063123122743e-16},{2242201373061537,7.339347561177405e-16},
	 {2242212329317416,7.370729905789831e-16},{2242222309184237,7.4022134917658e-16},
	 {2242231311537397,7.433801711647648e-16},{2242239334556717,7.465498018555889e-16},
	 {2242246375717369,7.497305929136979e-16},{2242252431779415,7.529229026624058e-16},
	 {2242257498775893,7.561270964017922e-16},{2242261571999416,7.5934354673958895e-16},
	 {2242264645987196,7.625726339356756e-16},{2242266714504453,7.658147462610487e-16},
	 {2242267770526109,7.690702803721919e-16},{2242267806216711,7.723396417018299e-16},
	 {2242266812908462,7.756232448671174e-16},{2242264781077289,7.789215140963852e-16},
	 {2242261700316818,7.822348836756411e-16},{2242257559310145,7.855637984161084e-16},
	 {2242252345799276,7.889087141441755e-16},{2242246046552082,7.922700982152271e-16},
	 {2242238647326615,7.956484300529366e-16},{2242230132832625,7.99044201715713e-16},
	 {2242220486690076,8.024579184921259e-16},{2242209691384458,8.058900995272657e-16},
	 {2242197728218684,8.093412784821501e-16},{2242184577261310,8.128120042284501e-16},
	 {2242170217290819,8.163028415809877e-16},{2242154625735679,8.198143720706533e-16},
	 {2242137778609839,8.23347194760605e-16},{2242119650443327,8.26901927108847e-16},
	 {2242100214207556,8.304792058805374e-16},{2242079441234906,8.340796881136629e-16},
	 {2242057301132135,8.377040521420222e-16},{2242033761687079,8.413529986798028e-16},
	 {2242008788768107,8.450272519724097e-16},{2241982346215682,8.487275610186155e-16},
	 {2241954395725356,8.524547008695596e-16},{2241924896721443,8.562094740106233e-16},
	 {2241893806220517,8.599927118327665e-16},{2241861078683830,8.638052762005259e-16},
	 {2241826665857598,8.676480611245582e-16},{2241790516600041,8.715219945473698e-16},
	 {2241752576693881,8.754280402517175e-16},{2241712788642916,8.793671999021043e-16},
	 {2241671091451078,8.833405152308408e-16},{2241627420382235,8.873490703813135e-16},
	 {2241581706698773,8.913939944224086e-16},{2241533877376767,8.954764640495068e-16},
	 {2241483854795281,8.9959770648911e-16},{2241431556397035,9.037590026260118e-16},
	 {2241376894317345,9.079616903740068e-16},{2241319774977817,9.122071683134846e-16},
	 {2241260098640860,9.164968996219135e-16},{2241197758920538,9.208324163262308e-16},
	 {2241132642244704,9.252153239095693e-16},{2241064627262652,9.296473063086417e-16},
	 {2240993584191742,9.341301313425265e-16},{2240919374095536,9.38665656618666e-16},
	 {2240841848084890,9.432558359676707e-16},{2240760846432232,9.479027264651738e-16},
	 {2240676197587784,9.526084961066279e-16},{2240587717084782,9.57375432209745e-16},
	 {2240495206318753,9.622059506294838e-16},{2240398451183567,9.671026058823054e-16},
	 {2240297220544165,9.720681022901626e-16},{2240191264522612,9.771053062707209e-16},
	 {2240080312570155,9.822172599190541e-16},{2239964071293331,9.874071960480671e-16},
	 {2239842221996530,9.926785548807976e-16},{2239714417896699,9.980350026183645e-16},
	 {2239580280957725,1.003480452143618e-15},{2239439398282193,1.0090190861637457e-15},
	 {2239291317986196,1.0146553831467086e-15},{2239135544468203,1.0203941464683124e-15},
	 {2238971532964979,1.0262405372613567e-15},{2238798683265269,1.0322001115486456e-15},
	 {2238616332424351,1.03827886235154e-15},{2238423746288095,1.044483267600047e-15},
	 {2238220109591890,1.0508203448355195e-15},{2238004514345216,1.057297713900989e-15},
	 {2237775946143212,1.06392366906768e-15},{2237533267957822,1.0707072623632994e-15},
	 {2237275200846753,1.0776584002668106e-15},{2237000300869952,1.0847879564403425e-15},
	 {2236706931309099,1.0921079038149563e-15},{2236393229029147,1.0996314701785628e-15},
	 {2236057063479501,1.1073733224935752e-15},{2235695986373246,1.1153497865853155e-15},
	 {2235307169458859,1.1235791107110833e-15},{2234887326941578,1.1320817840164846e-15},
	 {2234432617919447,1.140880924258278e-15},{2233938522519765,1.1500027537839792e-15},
	 {2233399683022677,1.159477189144919e-15},{2232809697779198,1.169338578691096e-15},
	 {2232160850599817,1.17962663529558e-15},{2231443750584641,1.190387629928289e-15},
	 {2230646845562170,1.2016759392543819e-15},{2229755753817986,1.2135560818666897e-15},
	 {2228752329126533,1.2261054417450561e-15},{2227613325162504,1.2394179789163251e-15},
	 {2226308442121174,1.2536093926602567e-15},{2224797391720399,1.268824481425501e-15},
	 {2223025347823832,1.2852479319096109e-15},{2220915633329809,1.3031206634689985e-15},
	 {2218357446087030,1.3227655770195326e-15},{2215184158448668,1.3446300925011171e-15},
	 {2211132412537369,1.3693606835128518e-15},{2205758503851065,1.397943667277524e-15},
	 {2198248265654987,1.4319989869661328e-15},{2186916352102141,1.4744848603597596e-15},
	 {2167562552481814,1.5317872741611144e-15},{2125549880839716,1.6227698675312968e-15}}).

normal_fi(Indx) ->
    element(Indx,
	    {1.0000000000000000e+00,9.7710170126767082e-01,9.5987909180010600e-01,
	     9.4519895344229909e-01,9.3206007595922991e-01,9.1999150503934646e-01,
	     9.0872644005213032e-01,8.9809592189834297e-01,8.8798466075583282e-01,
	     8.7830965580891684e-01,8.6900868803685649e-01,8.6003362119633109e-01,
	     8.5134625845867751e-01,8.4291565311220373e-01,8.3471629298688299e-01,
	     8.2672683394622093e-01,8.1892919160370192e-01,8.1130787431265572e-01,
	     8.0384948317096383e-01,7.9654233042295841e-01,7.8937614356602404e-01,
	     7.8234183265480195e-01,7.7543130498118662e-01,7.6863731579848571e-01,
	     7.6195334683679483e-01,7.5537350650709567e-01,7.4889244721915638e-01,
	     7.4250529634015061e-01,7.3620759812686210e-01,7.2999526456147568e-01,
	     7.2386453346862967e-01,7.1781193263072152e-01,7.1183424887824798e-01,
	     7.0592850133275376e-01,7.0009191813651117e-01,6.9432191612611627e-01,
	     6.8861608300467136e-01,6.8297216164499430e-01,6.7738803621877308e-01,
	     6.7186171989708166e-01,6.6639134390874977e-01,6.6097514777666277e-01,
	     6.5561147057969693e-01,6.5029874311081637e-01,6.4503548082082196e-01,
	     6.3982027745305614e-01,6.3465179928762327e-01,6.2952877992483625e-01,
	     6.2445001554702606e-01,6.1941436060583399e-01,6.1442072388891344e-01,
	     6.0946806492577310e-01,6.0455539069746733e-01,5.9968175261912482e-01,
	     5.9484624376798689e-01,5.9004799633282545e-01,5.8528617926337090e-01,
	     5.8055999610079034e-01,5.7586868297235316e-01,5.7121150673525267e-01,
	     5.6658776325616389e-01,5.6199677581452390e-01,5.5743789361876550e-01,
	     5.5291049042583185e-01,5.4841396325526537e-01,5.4394773119002582e-01,
	     5.3951123425695158e-01,5.3510393238045717e-01,5.3072530440366150e-01,
	     5.2637484717168403e-01,5.2205207467232140e-01,5.1775651722975591e-01,
	     5.1348772074732651e-01,5.0924524599574761e-01,5.0502866794346790e-01,
	     5.0083757512614835e-01,4.9667156905248933e-01,4.9253026364386815e-01,
	     4.8841328470545758e-01,4.8432026942668288e-01,4.8025086590904642e-01,
	     4.7620473271950547e-01,4.7218153846772976e-01,4.6818096140569321e-01,
	     4.6420268904817391e-01,4.6024641781284248e-01,4.5631185267871610e-01,
	     4.5239870686184824e-01,4.4850670150720273e-01,4.4463556539573912e-01,
	     4.4078503466580377e-01,4.3695485254798533e-01,4.3314476911265209e-01,
	     4.2935454102944126e-01,4.2558393133802180e-01,4.2183270922949573e-01,
	     4.1810064983784795e-01,4.1438753404089090e-01,4.1069314827018799e-01,
	     4.0701728432947315e-01,4.0335973922111429e-01,3.9972031498019700e-01,
	     3.9609881851583223e-01,3.9249506145931540e-01,3.8890886001878855e-01,
	     3.8534003484007706e-01,3.8178841087339344e-01,3.7825381724561896e-01,
	     3.7473608713789086e-01,3.7123505766823922e-01,3.6775056977903225e-01,
	     3.6428246812900372e-01,3.6083060098964775e-01,3.5739482014578022e-01,
	     3.5397498080007656e-01,3.5057094148140588e-01,3.4718256395679348e-01,
	     3.4380971314685055e-01,3.4045225704452164e-01,3.3711006663700588e-01,
	     3.3378301583071823e-01,3.3047098137916342e-01,3.2717384281360129e-01,
	     3.2389148237639104e-01,3.2062378495690530e-01,3.1737063802991350e-01,
	     3.1413193159633707e-01,3.1090755812628634e-01,3.0769741250429189e-01,
	     3.0450139197664983e-01,3.0131939610080288e-01,2.9815132669668531e-01,
	     2.9499708779996164e-01,2.9185658561709499e-01,2.8872972848218270e-01,
	     2.8561642681550159e-01,2.8251659308370741e-01,2.7943014176163772e-01,
	     2.7635698929566810e-01,2.7329705406857691e-01,2.7025025636587519e-01,
	     2.6721651834356114e-01,2.6419576399726080e-01,2.6118791913272082e-01,
	     2.5819291133761890e-01,2.5521066995466168e-01,2.5224112605594190e-01,
	     2.4928421241852824e-01,2.4633986350126363e-01,2.4340801542275012e-01,
	     2.4048860594050039e-01,2.3758157443123795e-01,2.3468686187232990e-01,
	     2.3180441082433859e-01,2.2893416541468023e-01,2.2607607132238020e-01,
	     2.2323007576391746e-01,2.2039612748015194e-01,2.1757417672433113e-01,
	     2.1476417525117358e-01,2.1196607630703015e-01,2.0917983462112499e-01,
	     2.0640540639788071e-01,2.0364274931033485e-01,2.0089182249465656e-01,
	     1.9815258654577511e-01,1.9542500351413428e-01,1.9270903690358912e-01,
	     1.9000465167046496e-01,1.8731181422380025e-01,1.8463049242679927e-01,
	     1.8196065559952254e-01,1.7930227452284767e-01,1.7665532144373500e-01,
	     1.7401977008183875e-01,1.7139559563750595e-01,1.6878277480121151e-01,
	     1.6618128576448205e-01,1.6359110823236570e-01,1.6101222343751107e-01,
	     1.5844461415592431e-01,1.5588826472447920e-01,1.5334316106026283e-01,
	     1.5080929068184568e-01,1.4828664273257453e-01,1.4577520800599403e-01,
	     1.4327497897351341e-01,1.4078594981444470e-01,1.3830811644855071e-01,
	     1.3584147657125373e-01,1.3338602969166913e-01,1.3094177717364430e-01,
	     1.2850872227999952e-01,1.2608687022018586e-01,1.2367622820159654e-01,
	     1.2127680548479021e-01,1.1888861344290998e-01,1.1651166562561080e-01,
	     1.1414597782783835e-01,1.1179156816383801e-01,1.0944845714681163e-01,
	     1.0711666777468364e-01,1.0479622562248690e-01,1.0248715894193508e-01,
	     1.0018949876880981e-01,9.7903279038862284e-02,9.5628536713008819e-02,
	     9.3365311912690860e-02,9.1113648066373634e-02,8.8873592068275789e-02,
	     8.6645194450557961e-02,8.4428509570353374e-02,8.2223595813202863e-02,
	     8.0030515814663056e-02,7.7849336702096039e-02,7.5680130358927067e-02,
	     7.3522973713981268e-02,7.1377949058890375e-02,6.9245144397006769e-02,
	     6.7124653827788497e-02,6.5016577971242842e-02,6.2921024437758113e-02,
	     6.0838108349539864e-02,5.8767952920933758e-02,5.6710690106202902e-02,
	     5.4666461324888914e-02,5.2635418276792176e-02,5.0617723860947761e-02,
	     4.8613553215868521e-02,4.6623094901930368e-02,4.4646552251294443e-02,
	     4.2684144916474431e-02,4.0736110655940933e-02,3.8802707404526113e-02,
	     3.6884215688567284e-02,3.4980941461716084e-02,3.3093219458578522e-02,
	     3.1221417191920245e-02,2.9365939758133314e-02,2.7527235669603082e-02,
	     2.5705804008548896e-02,2.3902203305795882e-02,2.2117062707308864e-02,
	     2.0351096230044517e-02,1.8605121275724643e-02,1.6880083152543166e-02,
	     1.5177088307935325e-02,1.3497450601739880e-02,1.1842757857907888e-02,
	     1.0214971439701471e-02,8.6165827693987316e-03,7.0508754713732268e-03,
	     5.5224032992509968e-03,4.0379725933630305e-03,2.6090727461021627e-03,
	     1.2602859304985975e-03}).
-endif.