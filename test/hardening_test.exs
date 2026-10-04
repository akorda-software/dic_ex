defmodule DicEx.HardeningTest do
  use ExUnit.Case, async: true

  alias DicEx.Parser
  alias DicEx.RNG.Deterministic

  describe "limits on untrusted input" do
    test "too many dice, too many sides and overlong input are rejected" do
      assert {:error, "too many dice" <> _} = DicEx.roll_e("101d6")
      assert {:error, "too many dice" <> _} = DicEx.roll_e("60d6+50d4")
      assert {:error, "dice cannot have" <> _} = DicEx.roll_e("1d1001")

      assert {:error, "expression is too long" <> _} =
               DicEx.roll_e(String.duplicate("1+", 200) <> "1")
    end

    test "limits are configurable per call" do
      assert {:ok, _} = DicEx.roll_e("150d6", max_dice: 200)
      assert {:error, _} = DicEx.roll_e("3d6", max_dice: 2)
    end

    test "never-ending modifiers are rejected" do
      assert {:error, "reroll condition" <> _} = DicEx.roll_e("1d6r<=6")
      assert {:error, "reroll condition" <> _} = DicEx.roll_e("1d1r1")
      assert {:error, "a d1 cannot explode"} = DicEx.roll_e("1d1!")
      # rerolling once can't loop, so it stays legal
      assert {:ok, _} = DicEx.roll_e("1d6ro<=6")
    end

    test "a biased RNG cannot loop a repeating reroll forever" do
      assert %DicEx.Result{total: 1} = DicEx.roll("1d20r1", rng: {Deterministic, []})
    end

    test "non-binary input returns an error tuple" do
      assert {:error, _} = DicEx.roll_e(nil)
      assert_raise ArgumentError, fn -> DicEx.roll(nil) end
    end

    test "trailing operators and comparators produce errors, not crashes" do
      for input <- ["5 !", "5<3", "1d20 ro", "3 %"] do
        assert {:error, _} = DicEx.roll_e(input), input
      end
    end

    test "non-integer deterministic outcomes raise a clear error" do
      assert_raise ArgumentError, ~r/must be integers/, fn ->
        DicEx.roll("1d20", rng: {Deterministic, ["20"]})
      end
    end
  end

  describe "notation" do
    test "percentile die" do
      assert {:ok, {:dice, 1, 100, []}} = Parser.parse("d%")
      assert {:ok, {:dice, 2, 100, [{:keep_high, 1}]}} = Parser.parse("2d%kh1")
    end

    test "leading sign applies to the first term" do
      assert DicEx.roll("-1d4+5", rng: {Deterministic, [3]}).total == 2
      assert DicEx.roll("+3").total == 3
      assert DicEx.roll("-3+1d4", rng: {Deterministic, [4]}).total == 1
    end

    test "double signs between terms are rejected" do
      assert {:error, _} = DicEx.roll_e("1d6--5")
      assert {:error, _} = DicEx.roll_e("1d6+-5")
    end

    test "only one reroll per pool" do
      assert {:error, "only one reroll" <> _} = DicEx.roll_e("1d6r1r2")
    end

    test "uppercase penetrate" do
      assert {:ok, {:dice, 1, 6, [{:explode, :penetrate}]}} = Parser.parse("1d6!P")
    end
  end

  describe ":seed" do
    test "is reproducible" do
      assert DicEx.roll("10d20", seed: 7) == DicEx.roll("10d20", seed: 7)
    end

    test "does not touch the caller's :rand state" do
      :rand.seed(:exsss, 123)
      expected = :rand.uniform(1_000_000)

      :rand.seed(:exsss, 123)
      DicEx.roll("1d20", seed: 1)
      assert :rand.uniform(1_000_000) == expected
    end
  end

  describe "roll_dice/3" do
    test "advantage and disadvantage cancel out" do
      result = DicEx.roll_dice(1, 20, advantage: true, disadvantage: true)
      assert result.expression == "1d20"
    end
  end
end
