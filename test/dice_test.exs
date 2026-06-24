defmodule DicEx.DiceTest do
  use ExUnit.Case, async: true

  doctest DicEx.Dice

  alias DicEx.Dice

  describe "catalog" do
    test "supported lists the polyhedral faces" do
      assert Dice.supported() == [4, 6, 8, 10, 12, 20, 100]
    end

    test "supported? accepts only the catalog" do
      for sides <- Dice.supported(), do: assert(Dice.supported?(sides))
      for sides <- [0, 1, 2, 3, 5, 7, 13, 50, 101], do: refute(Dice.supported?(sides))
    end
  end

  describe "faces/1" do
    test "standard dice run 1..sides" do
      assert Dice.faces(4) == [1, 2, 3, 4]
      assert Dice.faces(20) == Enum.to_list(1..20)
    end

    test "d100 is modelled as a tens die for display" do
      assert Dice.faces(100) == [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
    end
  end
end
