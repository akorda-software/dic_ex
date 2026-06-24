defmodule DicEx do
  readme = Path.expand("../README.md", __DIR__)
  @external_resource readme
  @moduledoc readme
             |> File.read!()
             |> String.split("<!-- MDOC -->")
             |> Enum.fetch!(1)

  alias DicEx.{Parser, Result, RNG, Roller}

  @default_rng RNG.Default

  @type roll_opt :: {:rng, module() | {module(), term()}} | {:seed, integer()}

  @doc """
  Rolls the given expression and returns a `DicEx.Result`.

  ## Options

    * `:seed` — integer seed for the default RNG (reproducible sequence).
    * `:rng` — an explicit RNG module (stateless) or `{module, state}` tuple.

  """
  @spec roll(binary(), [roll_opt()]) :: Result.t()
  def roll(expression, opts \\ [])

  def roll(expression, opts) when is_binary(expression) and is_list(opts) do
    rng = resolve_rng(opts)

    case Parser.parse(expression) do
      {:ok, ast} ->
        {result, _final_rng} = Roller.evaluate(ast, rng)
        %{result | expression: expression}

      {:error, reason} ->
        raise ArgumentError, "invalid dice expression #{inspect(expression)}: #{reason}"
    end
  end

  @doc """
  Like `roll/2` but returns `{:ok, result}` or `{:error, reason}` without
  raising. Handy when the expression comes from untrusted input (e.g. a chat
  command parsed by an LLM in dragonEx).
  """
  @spec roll_e(binary(), [roll_opt()]) :: {:ok, Result.t()} | {:error, String.t()}
  def roll_e(expression, opts \\ [])

  def roll_e(expression, opts) when is_binary(expression) and is_list(opts) do
    rng = resolve_rng(opts)

    with {:ok, ast} <- Parser.parse(expression) do
      {result, _} = Roller.evaluate(ast, rng)
      {:ok, %{result | expression: expression}}
    end
  end

  @doc """
  Convenience for a single typed roll — the shape the dragonEx UI emits.

      DicEx.roll_dice(2, 20)        # 2d20
      DicEx.roll_dice(1, 20, mod: 5) # 1d20 + 5

  ## Options

    * `:mod` — integer modifier added to the total (`+`/`-`).
    * `:advantage` — boolean, keeps highest of 2 (implies 2 dice if `count==1`).
    * `:disadvantage` — boolean, keeps lowest of 2.
    * Plus any option accepted by `roll/2` (`:seed`, `:rng`).
  """
  @spec roll_dice(pos_integer(), pos_integer(), keyword()) :: Result.t()
  def roll_dice(count, sides, opts \\ []) do
    base = "#{count}d#{sides}"

    expr =
      case {Keyword.get(opts, :advantage), Keyword.get(opts, :disadvantage)} do
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

    roll(expr, Keyword.take(opts, [:seed, :rng]))
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
        RNG.Seeded.seed(seed)
        @default_rng

      true ->
        @default_rng
    end
  end
end
