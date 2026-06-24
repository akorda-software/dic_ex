defmodule DicEx.Roller do
  @moduledoc false

  # Evaluates the parser's AST into a %DicEx.Result{}. The RNG is threaded
  # explicitly so a deterministic stub (tests) or a seeded default (reproducible
  # sessions) can be swapped in without touching the evaluator.

  alias DicEx.Result

  @doc """
  Evaluates an AST produced by `DicEx.Parser.parse/1`.

  `rng` is either a module implementing `DicEx.RNG` (stateless, e.g. the
  default `:rand`-backed one) or a `{module, state}` tuple for stateful RNGs
  such as the deterministic test stub. Returns `{%Result{}, final_rng}`.
  """
  def evaluate(ast, rng) do
    {groups, rng} = eval_node(ast, [], rng)

    total =
      groups
      |> Enum.reduce(0, fn
        %{subtotal: n}, acc when n >= 0 -> acc + n
        %{subtotal: n}, acc -> acc + n
      end)

    {%Result{expression: nil, total: total, groups: Enum.reverse(groups)}, rng}
  end

  defp eval_node({:num, n}, acc, rng), do: {[num_group(n) | acc], rng}

  defp eval_node({:dice, count, sides, mods}, acc, rng) do
    {group, rng} = roll_dice(count, sides, mods, rng)
    {[group | acc], rng}
  end

  defp eval_node({:op, op, left, right}, acc, rng) do
    {left_groups, rng} = eval_node(left, [], rng)
    {right_groups, rng} = eval_node(right, [], rng)

    # Operators only adjust the running subtotal; individual groups stay intact
    # so rendering/LLM data is never lossy.
    case {left_groups, right_groups} do
      {[lg], [rg]} ->
        sign = if op == :-, do: -1, else: 1
        merged = %{rg | subtotal: sign * rg.subtotal}
        {[merged, lg | acc], rng}

      _ ->
        {left_groups ++ right_groups ++ acc, rng}
    end
  end

  # --- dice pool evaluation ------------------------------------------------
  # Modifier application order (D&D conventional):
  #   1. reroll  — replaces qualifying base rolls
  #   2. explode — chains bonus dice on a max result
  #   3. keep/drop — selects the final pool

  defp roll_dice(count, sides, mods, rng) do
    {raw_rolls, rng} =
      Enum.map_reduce(1..count, rng, fn _, r ->
        roll_one(sides, mods, r)
      end)

    rolls = List.flatten(raw_rolls)

    {kept_rolls, applied} = apply_selection(rolls, mods)

    subtotal = kept_rolls |> Enum.map(& &1.value) |> Enum.sum()

    group = %{
      kind: :dice,
      notation: nil,
      sides: sides,
      subtotal: subtotal,
      modifiers: applied,
      rolls: mark_kept(rolls, kept_rolls)
    }

    {group, rng}
  end

  defp roll_one(sides, mods, rng) do
    {base, rng} = next_roll(sides, rng)
    {base, rng} = apply_reroll(base, sides, mods, rng)

    case explode_mode(mods) do
      nil ->
        {[%{value: base, kept: true, exploded: false}], rng}

      mode ->
        expand_explode(base, sides, mode, rng, [], 0)
    end
  end

  # Recursively explode a max result. `count` is how many dice are already in
  # the accumulator (0 == the triggering die). Penetrate subtracts 1 from every
  # bonus die's recorded value (min 1); the trigger die keeps full value.
  defp expand_explode(value, sides, mode, rng, acc, count) do
    is_trigger? = count == 0
    recorded = if is_trigger? or mode != :penetrate, do: value, else: max(value - 1, 1)
    entry = %{value: recorded, kept: true, exploded: not is_trigger?}

    cond do
      value == sides and length(acc) < 50 ->
        {next, rng} = next_roll(sides, rng)
        expand_explode(next, sides, mode, rng, [entry | acc], count + 1)

      true ->
        {Enum.reverse([entry | acc]), rng}
    end
  end

  defp apply_reroll(value, sides, mods, rng) do
    case reroll_spec(mods) do
      nil ->
        {value, rng}

      {op, threshold, mode} ->
        reroll_step(value, sides, op, threshold, mode, rng)
    end
  end

  defp reroll_step(value, sides, op, threshold, :repeat, rng) do
    if matches?(value, op, threshold) do
      {v, rng} = next_roll(sides, rng)
      reroll_step(v, sides, op, threshold, :repeat, rng)
    else
      {value, rng}
    end
  end

  defp reroll_step(value, sides, op, threshold, :once, rng) do
    if matches?(value, op, threshold) do
      next_roll(sides, rng)
    else
      {value, rng}
    end
  end

  defp matches?(v, :lt, t), do: v < t
  defp matches?(v, :le, t), do: v <= t
  defp matches?(v, :eq, t), do: v == t
  defp matches?(v, :ge, t), do: v >= t
  defp matches?(v, :gt, t), do: v > t

  defp reroll_spec(mods) do
    Enum.find_value(mods, fn
      {:reroll, op, v, mode} -> {op, v, mode}
      _ -> nil
    end)
  end

  # --- keep / drop selection ----------------------------------------------

  defp apply_selection(rolls, mods) do
    case selection(mods) do
      nil ->
        {rolls, []}

      {:keep_high, n} ->
        kept = top_n(rolls, n)
        {kept, [{:keep_high, n}]}

      {:keep_low, n} ->
        kept = bottom_n(rolls, n)
        {kept, [{:keep_low, n}]}

      {:drop_high, n} ->
        dropped = top_n(rolls, n)
        kept = rolls -- dropped
        {kept, [{:drop_high, n}]}

      {:drop_low, n} ->
        dropped = bottom_n(rolls, n)
        kept = rolls -- dropped
        {kept, [{:drop_low, n}]}
    end
  end

  # Only one selection modifier is meaningful per pool; last one wins.
  defp selection(mods) do
    mods
    |> Enum.filter(&match?({k, _} when k in [:keep_high, :keep_low, :drop_high, :drop_low], &1))
    |> List.last()
  end

  defp top_n(rolls, n) do
    rolls
    |> Enum.sort_by(& &1.value, :desc)
    |> Enum.take(n)
  end

  defp bottom_n(rolls, n) do
    rolls
    |> Enum.sort_by(& &1.value, :asc)
    |> Enum.take(n)
  end

  defp mark_kept(rolls, kept_rolls) do
    kept_set = kept_rolls |> Enum.map(&{&1.value, &1.exploded}) |> MapSet.new()

    {marked, _} =
      Enum.map_reduce(rolls, kept_set, fn roll, remaining ->
        key = {roll.value, roll.exploded}

        if MapSet.member?(remaining, key) do
          {%{roll | kept: true}, MapSet.delete(remaining, key)}
        else
          {%{roll | kept: false}, remaining}
        end
      end)

    marked
  end

  # --- helpers --------------------------------------------------------------

  defp explode_mode(mods) do
    Enum.find_value(mods, fn
      {:explode, mode} -> mode
      _ -> nil
    end)
  end

  defp num_group(n) do
    %{kind: :modifier, notation: nil, sides: nil, subtotal: n, modifiers: [], rolls: []}
  end

  # Pulls the next integer from whatever RNG flavour we were handed.
  defp next_roll(sides, {DicEx.RNG.Deterministic, _} = rng) do
    {value, rng} = DicEx.RNG.Deterministic.next(rng)

    value =
      case value do
        :exhausted -> 1
        v when v > sides -> rem(v - 1, sides) + 1
        v when v < 1 -> 1
        v -> v
      end

    {value, rng}
  end

  defp next_roll(sides, mod) when is_atom(mod) do
    {mod.roll(sides), mod}
  end
end
