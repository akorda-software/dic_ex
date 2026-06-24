defmodule DicExTest do
  use ExUnit.Case, async: true

  describe "roll/1 ranges" do
    test "a d20 stays within 1..20 across many rolls" do
      for _ <- 1..200 do
        total = DicEx.roll("1d20").total
        assert total in 1..20
      end
    end

    test "3d6 stays within 3..18" do
      for _ <- 1..200 do
        total = DicEx.roll("3d6").total
        assert total in 3..18
      end
    end

    test "advantage total is always one of the two rolled values" do
      for _ <- 1..100 do
        %DicEx.Result{groups: [group]} = DicEx.roll("2d20kh1")
        values = Enum.map(group.rolls, & &1.value)
        assert group.subtotal == Enum.max(values)
      end
    end

    test "drop-lowest 4d6 is within 3..18" do
      for _ <- 1..100 do
        total = DicEx.roll("4d6dl1").total
        assert total in 3..18
      end
    end
  end

  describe "seeded reproducibility" do
    test "same seed yields same sequence" do
      a = DicEx.roll("4d6", seed: 99).total
      b = DicEx.roll("4d6", seed: 99).total
      assert a == b
    end
  end

  describe "roll_dice/3" do
    test "builds basic notation" do
      assert %DicEx.Result{} = DicEx.roll_dice(2, 20, seed: 1)
    end

    test "advantage on a single die becomes 2dXkh1" do
      result = DicEx.roll_dice(1, 20, advantage: true, rng: {DicEx.RNG.Deterministic, [4, 18]})
      assert result.expression == "2d20kh1"
      assert result.total == 18
    end

    test "modifier is appended" do
      result = DicEx.roll_dice(1, 20, mod: 5, rng: {DicEx.RNG.Deterministic, [12]})
      assert result.expression == "1d20+5"
      assert result.total == 17
    end

    test "negative modifier" do
      result = DicEx.roll_dice(1, 20, mod: -3, rng: {DicEx.RNG.Deterministic, [12]})
      assert result.expression == "1d20-3"
      assert result.total == 9
    end
  end

  describe "roll_e/2" do
    test "returns ok tuple on valid input" do
      assert {:ok, %DicEx.Result{}} = DicEx.roll_e("1d20")
    end

    test "returns error tuple on invalid input" do
      assert {:error, _} = DicEx.roll_e("nope")
    end
  end

  describe "roll/2 errors" do
    test "raises ArgumentError on invalid expression" do
      assert_raise ArgumentError, fn -> DicEx.roll("not dice") end
    end
  end

  describe "format/1" do
    test "pretty prints" do
      result = DicEx.roll_dice(1, 20, mod: 5, rng: {DicEx.RNG.Deterministic, [12]})
      assert DicEx.format(result) == "1d20+5 = 17"
    end
  end
end
