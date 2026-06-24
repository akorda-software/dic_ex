defmodule DicEx.RollerTest do
  use ExUnit.Case, async: true

  alias DicEx.{Parser, Roller, Result}
  alias DicEx.RNG.Deterministic

  # Roll via the deterministic RNG so every value is pinned.
  defp roll(expr, outcomes) do
    {:ok, ast} = Parser.parse(expr)
    {result, _rng} = Roller.evaluate(ast, {Deterministic, outcomes})
    result
  end

  defp dice_rolls(result) do
    result.groups
    |> Enum.filter(&(&1.kind == :dice))
    |> Enum.flat_map(& &1.rolls)
  end

  describe "plain rolls" do
    test "single die returns its value" do
      assert roll("1d6", [4]).total == 4
    end

    test "multiple dice sum" do
      assert roll("3d6", [2, 5, 3]).total == 10
    end

    test "values above sides wrap into range" do
      # a "9" outcome on a d6 wraps to 3
      assert roll("1d6", [9]).total == 3
    end
  end

  describe "exploding dice" do
    test "chains on a max result" do
      result = roll("1d6!", [6, 6, 3])
      assert result.total == 15
      rolls = dice_rolls(result)
      assert length(rolls) == 3
      assert [%{exploded: false}, %{exploded: true}, %{exploded: true}] = rolls
    end

    test "no chain on a non-max result" do
      result = roll("1d6!", [4])
      assert result.total == 4
      assert [%{exploded: false}] = dice_rolls(result)
    end

    test "penetrate subtracts 1 from bonus dice" do
      result = roll("1d6!p", [6, 6, 3])
      assert result.total == 13
    end
  end

  describe "keep / drop" do
    test "keep high (advantage)" do
      result = roll("2d20kh1", [4, 18])
      assert result.total == 18
      [low, high] = dice_rolls(result)
      assert low.kept == false
      assert high.kept == true
    end

    test "keep low (disadvantage)" do
      result = roll("2d20kl1", [4, 18])
      assert result.total == 4
    end

    test "drop low keeps the rest" do
      result = roll("4d6dl1", [1, 2, 6, 3])
      assert result.total == 11
    end

    test "drop high" do
      result = roll("3d6dh1", [6, 2, 4])
      assert result.total == 6
    end

    test "keep high n" do
      result = roll("4d6kh2", [5, 1, 6, 3])
      assert result.total == 11
    end
  end

  describe "reroll" do
    test "repeat rerolls until the condition fails" do
      result = roll("1d20r1", [1, 1, 12])
      assert result.total == 12
    end

    test "once rerolls only a single time" do
      result = roll("1d20ro1", [1, 1])
      assert result.total == 1
    end

    test "explicit comparator" do
      result = roll("1d6r<3", [2, 2, 5])
      assert result.total == 5
    end
  end

  describe "expressions" do
    test "pool plus constant" do
      result = roll("2d6+5", [3, 4])
      assert result.total == 12
    end

    test "two pools" do
      result = roll("1d8+2d6", [7, 3, 5])
      assert result.total == 15
    end

    test "subtraction" do
      result = roll("1d20-2", [15])
      assert result.total == 13
    end
  end

  describe "result shape" do
    test "groups expose kind, subtotal and notation-less rolls" do
      result = roll("1d6+3", [4])
      assert %Result{} = result
      [dice, mod] = result.groups
      assert dice.kind == :dice
      assert dice.subtotal == 4
      assert dice.sides == 6
      assert mod.kind == :modifier
      assert mod.subtotal == 3
    end

    test "to_map produces JSON-friendly data" do
      result = roll("1d6", [5])
      map = Result.to_map(result)
      assert is_integer(map.total)
      assert [%{rolls: [%{value: 5, kept: true}]} | _] = map.groups
    end

    test "kept_values flattens kept dice" do
      result = roll("3d6kh1", [2, 5, 3])
      assert Result.kept_values(result) == [5]
    end
  end
end
