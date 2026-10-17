%% SPDX-License-Identifier: Apache-2.0

%%% The bridge between Pooka's Json values and Erlang's own `json` module.
%%%
%%% Decoding is done by `json:decode/3`, which lets the caller decide what each
%%% value becomes. Every value is handed to a Pooka constructor as soon as it is
%%% read, so the document is built once, in its final shape, with no second
%%% pass over a tree of Erlang terms.
%%%
%%% Encoding walks the tree in Pooka. This side only supplies the two pieces
%%% that need care: escaping a string and printing a float.
-module(pooka_json_ffi).

-export([decode/1, decode_limited/3, encode_string/1, encode_float/1, join/1]).

%% Json values are opaque here. They are made with their constructors and
%% never taken apart, as the BEAM interop guide asks.
-define(JSON, 'pooka@pooka_json@pooka@json').

%% Decode one JSON document.
%%
%% Returns `{ok, Json}` or `{error, JsonError}`, which Pooka reads as a Result.
decode(Text) ->
    Null = ?JSON:'$class@JNull@new'(),
    Decoders = #{
        null => Null,
        integer => fun(Digits) -> ?JSON:'$class@JInt@new'(binary_to_integer(Digits)) end,
        float => fun decode_float/1,
        array_push => fun(Value, Items) -> [wrap(Value) | Items] end,
        array_finish => fun(Items, Outer) ->
            {?JSON:'$class@JArray@new'(lists:reverse(Items)), Outer}
        end,
        object_push => fun(Key, Value, Entries) -> [{Key, wrap(Value)} | Entries] end,
        object_finish => fun(Entries, Outer) ->
            {?JSON:'$class@JObject@new'(lists:reverse(Entries)), Outer}
        end
    },
    try json:decode(Text, ok, Decoders) of
        {Value, ok, Rest} ->
            case trailing(Rest) of
                none -> {ok, wrap(Value)};
                Byte -> {error, ?JSON:'$class@InvalidByte@new'(Byte)}
            end
    catch
        throw:{pooka_number_out_of_range, Digits} ->
            {error, ?JSON:'$class@NumberOutOfRange@new'(Digits)};
        error:unexpected_end ->
            {error, ?JSON:'$class@UnexpectedEnd@new'()};
        error:{invalid_byte, Byte} ->
            {error, ?JSON:'$class@InvalidByte@new'(Byte)};
        error:{unexpected_sequence, Bytes} ->
            {error, sequence_error(Bytes)}
    end.

%% Strings and booleans arrive as plain Erlang terms, because object keys must
%% stay plain strings. Everything else has been wrapped by its decoder already.
wrap(Value) when is_binary(Value) -> ?JSON:'$class@JString@new'(Value);
wrap(true) -> ?JSON:'$class@JBool@new'(true);
wrap(false) -> ?JSON:'$class@JBool@new'(false);
wrap(Value) -> Value.

%% Only whitespace may follow the document.
trailing(<<Byte, Rest/binary>>) when Byte =:= $\s; Byte =:= $\t; Byte =:= $\n; Byte =:= $\r ->
    trailing(Rest);
trailing(<<>>) -> none;
trailing(<<Byte, _/binary>>) -> Byte.

%% The offending bytes may not be valid UTF-8, and a Pooka String must be.
printable(Bytes) ->
    case unicode:characters_to_binary(Bytes) of
        Text when is_binary(Text) -> Text;
        _ -> iolist_to_binary(io_lib:format("~w", [Bytes]))
    end.

%% A string with its quotes and escapes.
encode_string(Text) -> iolist_to_binary(json:encode_binary(Text)).

%% The shortest text that reads back as the same float.
encode_float(Float) -> float_to_binary(Float, [short]).

%% Glue the pieces of a document, which were collected newest first.
join(Pieces) -> iolist_to_binary(lists:reverse(Pieces)).


%% Keep numeric range failures separate from malformed string escapes. OTP
%% normalizes exponent-only spelling before invoking the Float callback.
decode_float(Digits) ->
    Number = try binary_to_float(Digits)
             catch error:badarg -> throw({pooka_number_out_of_range, Digits}) end,
    ?JSON:'$class@JFloat@new'(Number).

%% Scan depth before constructing the typed tree. Quotes and escaped backslashes
%% are handled byte-wise; the native parser still owns full syntax validation.
decode_limited(Text, Bytes, _Depth) when Bytes < 0; byte_size(Text) > Bytes ->
    {error, ?JSON:'$class@LimitExceeded@new'(<<"byte">>)};
decode_limited(_Text, _Bytes, Depth) when Depth < 0 ->
    {error, ?JSON:'$class@LimitExceeded@new'(<<"depth">>)};
decode_limited(Text, _Bytes, Depth) ->
    case within_depth(Text, Depth, 0, false, false) of
        true -> decode(Text);
        false -> {error, ?JSON:'$class@LimitExceeded@new'(<<"depth">>)}
    end.

within_depth(<<>>, _, _, _, _) -> true;
within_depth(<<_, Rest/binary>>, Limit, Depth, true, true) ->
    within_depth(Rest, Limit, Depth, true, false);
within_depth(<<$\\, Rest/binary>>, Limit, Depth, true, false) ->
    within_depth(Rest, Limit, Depth, true, true);
within_depth(<<$", Rest/binary>>, Limit, Depth, true, false) ->
    within_depth(Rest, Limit, Depth, false, false);
within_depth(<<_, Rest/binary>>, Limit, Depth, true, false) ->
    within_depth(Rest, Limit, Depth, true, false);
within_depth(<<$", Rest/binary>>, Limit, Depth, false, _) ->
    within_depth(Rest, Limit, Depth, true, false);
within_depth(<<Open, Rest/binary>>, Limit, Depth, false, _) when Open =:= $[; Open =:= ${ ->
    Depth < Limit andalso within_depth(Rest, Limit, Depth + 1, false, false);
within_depth(<<Close, Rest/binary>>, Limit, Depth, false, _) when Close =:= $]; Close =:= $} ->
    within_depth(Rest, Limit, max(0, Depth - 1), false, false);
within_depth(<<_, Rest/binary>>, Limit, Depth, false, _) ->
    within_depth(Rest, Limit, Depth, false, false).


%% OTP may reject overflow before invoking a custom Float callback. Its numeric
%% token still has valid JSON syntax; do not describe it as a string escape.
sequence_error(Bytes) ->
    Pattern = <<"^-?(0|[1-9][0-9]*)([.][0-9]+)?([eE][+-]?[0-9]+)?$">>,
    case re:run(Bytes, Pattern, [{capture, none}]) of
        match -> ?JSON:'$class@NumberOutOfRange@new'(Bytes);
        nomatch -> ?JSON:'$class@UnexpectedSequence@new'(printable(Bytes))
    end.
