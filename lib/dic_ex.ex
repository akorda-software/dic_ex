defmodule DicEx do
  readme = Path.expand("../README.md", __DIR__)
  @external_resource readme
  @moduledoc readme
             |> File.read!()
             |> String.split("<!-- MDOC -->")
             |> Enum.fetch!(1)

  alias DicEx.{Parser, Result, RNG, Roller}

  @default_rng RNG.Default

  @doc """
  Capabilities of the bundled renderer, so hosts can feature-detect across
  package versions. `authoritative_3d: true` means the 3D hook accepts
  `authoritative: true` roll events and settles on the supplied faces.
  """
  @spec renderer_capabilities() :: %{authoritative_3d: boolean()}
  def renderer_capabilities, do: %{authoritative_3d: true}

  @type roll_opt ::
          {:rng, module() | {module(), term()}}
          | {:seed, integer()}
          | {:max_dice, pos_integer()}
          | {:max_sides, pos_integer()}
          | {:max_length, pos_integer()}

  @parse_opts [:max_dice, :max_sides, :max_length]

  @doc """
  Rolls the given expression and returns a `DicEx.Result`.

  ## Options

    * `:seed` — integer seed for a reproducible sequence. The seeded state is
      private to the call; the caller's `:rand` state is left untouched.
    * `:rng` — an explicit RNG module (stateless) or `{module, state}` tuple.
    * `:max_dice` — maximum total dice across the expression (default `100`).
    * `:max_sides` — maximum sides per die (default `1000`).
    * `:max_length` — maximum expression length in characters (default `256`).

  Expressions that would never finish (`1d6r<=6`, `1d1!`) are rejected.
  """
  @spec roll(term(), [roll_opt()]) :: Result.t()
  def roll(expression, opts \\ [])

  def roll(expression, opts) when is_binary(expression) and is_list(opts) do
    case roll_e(expression, opts) do
      {:ok, result} ->
        result

      {:error, reason} ->
        raise ArgumentError, "invalid dice expression #{inspect(expression)}: #{reason}"
    end
  end

  def roll(expression, _opts) do
    raise ArgumentError, "dice expression must be a string, got: #{inspect(expression)}"
  end

  @doc """
  Like `roll/2` but returns `{:ok, result}` or `{:error, reason}` without
  raising. Handy when the expression comes from untrusted input (e.g. a chat
  command parsed by an LLM in dragonEx).
  """
  @spec roll_e(term(), [roll_opt()]) :: {:ok, Result.t()} | {:error, String.t()}
  def roll_e(expression, opts \\ [])

  def roll_e(expression, opts) when is_binary(expression) and is_list(opts) do
    with {:ok, ast} <- Parser.parse(expression, Keyword.take(opts, @parse_opts)) do
      {result, _} = Roller.evaluate(ast, resolve_rng(opts))
      {:ok, %{result | expression: expression}}
    end
  end

  def roll_e(expression, _opts) when not is_binary(expression),
    do: {:error, "dice expression must be a string"}

  @doc """
  Convenience for a single typed roll — the shape the dragonEx UI emits.

      DicEx.roll_dice(2, 20)        # 2d20
      DicEx.roll_dice(1, 20, mod: 5) # 1d20 + 5

  ## Options

    * `:mod` — integer modifier added to the total (`+`/`-`).
    * `:advantage` — boolean, keeps highest of 2 (only when `count == 1`).
    * `:disadvantage` — boolean, keeps lowest of 2 (only when `count == 1`).
      Advantage and disadvantage together cancel out (D&D 5e), rolling one die.
    * Plus any option accepted by `roll/2` (`:seed`, `:rng`).
  """
  @spec roll_dice(pos_integer(), pos_integer(), keyword()) :: Result.t()
  def roll_dice(count, sides, opts \\ []) do
    base = "#{count}d#{sides}"

    expr =
      case {Keyword.get(opts, :advantage), Keyword.get(opts, :disadvantage)} do
        {true, true} -> base
        {true, _} when count == 1 -> "2d#{sides}kh1"
        {_, true} when count == 1 -> "2d#{sides}kl1"
        _ -> base
      end

    expr =
      case Keyword.get(opts, :mod) do
        nil -> expr
        n when n >= 0 -> "#{expr}+#{n}"
        n -> "#{expr}#{n}"
      end

    roll(expr, Keyword.take(opts, [:seed, :rng | @parse_opts]))
  end

  @doc """
  Pretty-prints a result as a human readable string, e.g. `"2d20kh1+5 = 23"`.
  """
  @spec format(Result.t()) :: String.t()
  def format(%Result{} = result) do
    "#{result.expression} = #{result.total}"
  end

  # ---------------------------------------------------------------------------

  defp resolve_rng(opts) do
    cond do
      rng = Keyword.get(opts, :rng) ->
        rng

      seed = Keyword.get(opts, :seed) ->
        RNG.Seeded.new(seed)

      true ->
        @default_rng
    end
  end
end
