defmodule DicEx.Parser do
  @moduledoc false

  # Hand-rolled recursive-descent parser for D&D-style dice notation.
  #
  # Grammar (kept tight on purpose):
  #
  #   expr        := term (("+" | "-") term)*
  #   term        := dice | number
  #   dice        := [count] "d" sides modifier*
  #   modifier    := keep_high | keep_low | drop_high | drop_low
  #                 | explode | reroll
  #   keep_high   := "kh" number?        # advantage
  #   keep_low    := "kl" number?        # disadvantage
  #   drop_high   := "dh" number?
  #   drop_low    := "dl" number?
  #   explode     := "!" | "!p"          # penetrate subtracts 1 from chains
  #   reroll      := "r" [op] number ["o"] | "ro" [op] number
  #   op          := "<" | "<=" | "=" | ">=" | ">"
  #
  # count and sides are positive integers. A bare "d20" means "1d20".

  @comparators %{
    "<" => :lt,
    "<=" => :le,
    "=" => :eq,
    ">=" => :ge,
    ">" => :gt
  }

  # AST nodes:
  #   {:num, integer}
  #   {:dice, count, sides, [modifier]}
  #   {:op, :+ | :-, left, right}
  #
  # modifier:
  #   {:keep_high, n} | {:keep_low, n} | {:drop_high, n} | {:drop_low, n}
  #   {:explode, :standard | :penetrate}
  #   {:reroll, :lt|:le|:eq|:ge|:gt, value, :once | :repeat}

  @doc """
  Parses a dice expression into an AST, or returns `{:error, message}`.
  """
  def parse(input) when is_binary(input) do
    input = String.trim(input)

    try do
      with {:ok, tokens} <- tokenize(input),
           {:ok, ast, rest} <- parse_expr(tokens),
           :ok <- ensure_consumed(rest) do
        {:ok, ast}
      end
    catch
      {:parse_error, msg} -> {:error, msg}
    end
  end

  defp ensure_consumed([]), do: :ok
  defp ensure_consumed(rest), do: {:error, "unexpected trailing input: #{format_tokens(rest)}"}

  defp format_tokens(tokens) do
    tokens
    |> Enum.map_join(" ", fn
      {:int, n} -> "#{n}"
      t -> "#{t}"
    end)
  end

  # ---------------------------------------------------------------- tokenizing

  defp tokenize(""), do: {:error, "empty expression"}

  defp tokenize(input) do
    tokenize(input, [], [])
  end

  defp tokenize(<<>>, _buf, acc), do: {:ok, Enum.reverse(acc) |> List.flatten()}

  defp tokenize(<<c, rest::binary>>, [], acc) when c in ~c" \t\n\r", do: tokenize(rest, [], acc)

  defp tokenize(<<"!", rest::binary>>, _buf, acc) do
    case rest do
      <<"p", r2::binary>> -> tokenize(r2, [], [{:explode, :penetrate} | acc])
      _ -> tokenize(rest, [], [{:explode, :standard} | acc])
    end
  end

  defp tokenize(<<c, _::binary>> = rest, [], acc) when c in ?0..?9 do
    {digits, remaining} = take_digits(rest)
    {n, ""} = Integer.parse(digits)
    tokenize(remaining, [], [{:int, n} | acc])
  end

  defp tokenize(<<c, _::binary>> = rest, [], acc) when c in ?a..?z or c in ?A..?Z do
    {word, remaining} = take_letters(rest)

    case word |> String.downcase() |> keyword_token() do
      {:ok, token} -> tokenize(remaining, [], [token | acc])
      :error -> {:error, "unknown keyword #{inspect(word)}"}
    end
  end

  defp tokenize(<<c, rest::binary>>, [], acc) when c in ~c"<>=" do
    {sym, remaining} = take_comparator(<<c, rest::binary>>)
    tokenize(remaining, [], [{:cmp, Map.fetch!(@comparators, sym)} | acc])
  end

  defp tokenize(<<c, rest::binary>>, [], acc) when c in ~c"+-" do
    tokenize(rest, [], [op_token(c) | acc])
  end

  defp tokenize(other, _buf, _acc) do
    {:error, "unexpected character at #{inspect(String.slice(other, 0, 8))}"}
  end

  defp take_digits(bin), do: consume(bin, fn c -> c in ?0..?9 end)
  defp take_letters(bin), do: consume(bin, fn c -> c in ?a..?z or c in ?A..?Z end)

  defp consume(bin, fun), do: do_consume(bin, fun, <<>>)

  defp do_consume(<<c, rest::binary>>, fun, acc) do
    if fun.(c) do
      do_consume(rest, fun, <<acc::binary, c::utf8>>)
    else
      {acc, <<c, rest::binary>>}
    end
  end

  defp do_consume(<<>>, _fun, acc), do: {acc, <<>>}

  defp take_comparator(<<"<=", rest::binary>>), do: {"<=", rest}
  defp take_comparator(<<">=", rest::binary>>), do: {">=", rest}
  defp take_comparator(<<"=", rest::binary>>), do: {"=", rest}
  defp take_comparator(<<"<", rest::binary>>), do: {"<", rest}
  defp take_comparator(<<">", rest::binary>>), do: {">", rest}

  defp keyword_token("d"), do: {:ok, :d}
  defp keyword_token("kh"), do: {:ok, :kh}
  defp keyword_token("kl"), do: {:ok, :kl}
  defp keyword_token("dh"), do: {:ok, :dh}
  defp keyword_token("dl"), do: {:ok, :dl}
  defp keyword_token("ro"), do: {:ok, :reroll_once}
  defp keyword_token("r"), do: {:ok, :reroll}
  defp keyword_token(_), do: :error

  defp op_token(?+), do: :add
  defp op_token(?-), do: :sub

  # ----------------------------------------------------------------- parsing

  defp parse_expr(tokens) do
    with {:ok, left, rest} <- parse_term(tokens) do
      parse_expr_rest(rest, left)
    end
  end

  defp parse_expr_rest([:add | rest], left) do
    with {:ok, right, rest} <- parse_term(rest), do: parse_expr_rest(rest, {:op, :+, left, right})
  end

  defp parse_expr_rest([:sub | rest], left) do
    with {:ok, right, rest} <- parse_term(rest), do: parse_expr_rest(rest, {:op, :-, left, right})
  end

  defp parse_expr_rest(rest, left), do: {:ok, left, rest}

  defp parse_term(tokens) do
    case tokens do
      # dice with explicit count: <int> d <int> ...
      [{:int, count}, :d | _] = t when count > 0 ->
        parse_dice(t)

      # bare dice: d <int> ...
      [:d | _] = t ->
        parse_dice(t)

      [{:int, n}] ->
        {:ok, {:num, n}, []}

      [{:int, n} | rest] ->
        {:ok, {:num, n}, rest}

      [:sub, {:int, n} | rest] ->
        {:ok, {:num, -n}, rest}

      _ ->
        {:error, "expected a dice pool or number"}
    end
  end

  defp parse_dice([{:int, count}, :d, {:int, sides} | rest]) when count > 0 and sides > 0 do
    {mods, rest} = parse_modifiers(rest, [])
    {:ok, {:dice, count, sides, mods}, rest}
  end

  defp parse_dice([{:int, count}, :d, {:int, sides} | _]) when not (count > 0 and sides > 0) do
    {:error, "dice count and sides must be positive"}
  end

  defp parse_dice([:d, {:int, sides} | rest]) when sides > 0 do
    {mods, rest} = parse_modifiers(rest, [])
    {:ok, {:dice, 1, sides, mods}, rest}
  end

  defp parse_dice(_), do: {:error, "malformed dice pool"}

  defp parse_modifiers([{:explode, mode} | rest], acc)
       when mode in [:standard, :penetrate] do
    parse_modifiers(rest, [{:explode, mode} | acc])
  end

  defp parse_modifiers([kind | [{:int, n} | rest]], acc)
       when kind in [:kh, :kl, :dh, :dl] and n > 0 do
    parse_modifiers(rest, [{modifier_kind(kind), n} | acc])
  end

  defp parse_modifiers([kind | rest], acc) when kind in [:kh, :kl, :dh, :dl] do
    parse_modifiers(rest, [{modifier_kind(kind), 1} | acc])
  end

  defp parse_modifiers([reroll_kind | rest], acc) when reroll_kind in [:reroll, :reroll_once] do
    parse_reroll(rest, reroll_kind, acc)
  end

  defp parse_modifiers(rest, acc), do: {Enum.reverse(acc), rest}

  defp parse_reroll([{:cmp, op}, {:int, v} | rest], kind, acc) when v > 0 do
    mode = if kind == :reroll_once, do: :once, else: :repeat
    parse_modifiers(rest, [{:reroll, op, v, mode} | acc])
  end

  defp parse_reroll([{:int, v} | rest], kind, acc) when v > 0 do
    # bare `r<n>` rerolls values <= n (the common "reroll 1s" shorthand)
    mode = if kind == :reroll_once, do: :once, else: :repeat
    parse_modifiers(rest, [{:reroll, :le, v, mode} | acc])
  end

  defp parse_reroll(_rest, _kind, _acc),
    do: throw({:parse_error, "reroll needs a threshold value"})

  defp modifier_kind(:kh), do: :keep_high
  defp modifier_kind(:kl), do: :keep_low
  defp modifier_kind(:dh), do: :drop_high
  defp modifier_kind(:dl), do: :drop_low
end
