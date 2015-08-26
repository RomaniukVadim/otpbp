-module(otpbp_error_handler).

-ifndef(HAVE_error_handler__raise_undef_exception_3).
-export([raise_undef_exception/3]).
-endif.

-ifndef(HAVE_error_handler__raise_undef_exception_3).
raise_undef_exception(Module, Func, Args) ->
    try erlang:error(undef)
    catch error:undef ->
        Stk = [{Module, Func, Args, []}|tl(erlang:get_stacktrace())],
        erlang:raise(error, undef, Stk)
    end.
-endif.