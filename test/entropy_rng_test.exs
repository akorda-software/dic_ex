defmodule DicEx.RNG.EntropyTest do
  use ExUnit.Case, async: true

  alias DicEx.RNG.Entropy

  describe "roll/1 range" do
    test "stays within 1..sides for every supported die" do
      for sides <- [4, 6, 8, 10, 12, 20, 100], _ <- 1..200 do
        assert Entropy.roll(sides) in 1..sides
      end
    end

    test "d6 covers the whole face space over enough rolls" do
      seen =
        1..1000
        |> Enum.map(fn _ -> Entropy.roll(6) end)
        |> MapSet.new()

      assert MapSet.new(1..6) == MapSet.intersection(seen, MapSet.new(1..6))
    end

    test "d20 covers the whole face space over enough rolls" do
      seen =
        1..4000
        |> Enum.map(fn _ -> Entropy.roll(20) end)
        |> MapSet.new()

      assert MapSet.new(1..20) |> MapSet.subset?(seen)
    end
  end

  describe "uniformity" do
    test "d6 faces are roughly even (each within +/-25% of expected)" do
      counts =
        1..6000
        |> Enum.map(fn _ -> Entropy.roll(6) end)
        |> Enum.frequencies()

      for face <- 1..6 do
        assert_in_delta counts[face] || 0, 1000, 250
      end
    end
  end

  describe "wiring through DicEx.roll/2" do
    test "rng: DicEx.RNG.Entropy produces in-range rolls" do
      for _ <- 1..100 do
        assert DicEx.roll("1d20", rng: Entropy).total in 1..20
      end
    end

    test "is not reproducible across calls (unlike the seeded default)" do
      # a thousand-pool roll is effectively certain to differ on redraw
      a = DicEx.roll("100d20", rng: Entropy).total
      b = DicEx.roll("100d20", rng: Entropy).total
      refute a == b
    end
  end
end
