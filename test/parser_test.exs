defmodule DicEx.ParserTest do
  use ExUnit.Case, async: true

  alias DicEx.Parser

  describe "basic pools" do
    test "single die with explicit count" do
      assert {:ok, {:dice, 3, 6, []}} = Parser.parse("3d6")
    end

    test "bare die defaults to count 1" do
      assert {:ok, {:dice, 1, 20, []}} = Parser.parse("d20")
    end

    test "uppercase D is accepted" do
      assert {:ok, {:dice, 2, 8, []}} = Parser.parse("2D8")
    end

    test "all supported polyhedral faces" do
      for sides <- [4, 6, 8, 10, 12, 20, 100] do
        assert {:ok, {:dice, 1, ^sides, []}} = Parser.parse("d#{sides}")
      end
    end
  end

  describe "modifiers" do
    test "keep high with and without count" do
      assert {:ok, {:dice, 2, 20, [{:keep_high, 1}]}} = Parser.parse("2d20kh")
      assert {:ok, {:dice, 3, 6, [{:keep_high, 2}]}} = Parser.parse("3d6kh2")
    end

    test "keep low / drop high / drop low" do
      assert {:ok, {:dice, 2, 20, [{:keep_low, 1}]}} = Parser.parse("2d20kl")
      assert {:ok, {:dice, 4, 6, [{:drop_high, 1}]}} = Parser.parse("4d6dh1")
      assert {:ok, {:dice, 4, 6, [{:drop_low, 1}]}} = Parser.parse("4d6dl1")
    end

    test "explode variants" do
      assert {:ok, {:dice, 8, 6, [{:explode, :standard}]}} = Parser.parse("8d6!")
      assert {:ok, {:dice, 1, 6, [{:explode, :penetrate}]}} = Parser.parse("1d6!p")
    end

    test "reroll bare defaults to <= and repeat" do
      assert {:ok, {:dice, 1, 20, [{:reroll, :le, 1, :repeat}]}} = Parser.parse("1d20r1")
    end

    test "reroll with explicit comparator" do
      assert {:ok, {:dice, 1, 6, [{:reroll, :lt, 3, :repeat}]}} = Parser.parse("1d6r<3")
      assert {:ok, {:dice, 1, 6, [{:reroll, :ge, 5, :repeat}]}} = Parser.parse("1d6r>=5")
    end

    test "reroll once" do
      assert {:ok, {:dice, 1, 20, [{:reroll, :le, 2, :once}]}} = Parser.parse("1d20ro2")
    end

    test "stacked modifiers" do
      assert {:ok, {:dice, 4, 6, [{:explode, :standard}, {:drop_low, 1}]}} =
               Parser.parse("4d6!dl1")
    end
  end

  describe "expressions" do
    test "addition of pool and constant" do
      assert {:ok, {:op, :+, {:dice, 1, 20, []}, {:num, 5}}} = Parser.parse("1d20+5")
    end

    test "subtraction" do
      assert {:ok, {:op, :-, {:dice, 2, 6, []}, {:num, 3}}} = Parser.parse("2d6-3")
    end

    test "multiple pools" do
      assert {:ok, {:op, :+, {:op, :+, {:dice, 1, 8, []}, {:dice, 2, 6, []}}, {:num, 2}}} =
               Parser.parse("1d8+2d6+2")
    end

    test "whitespace is ignored" do
      assert {:ok, {:op, :+, {:dice, 3, 6, []}, {:num, 2}}} = Parser.parse("  3d6  + 2 ")
    end
  end

  describe "errors" do
    test "empty" do
      assert {:error, _} = Parser.parse("")
    end

    test "missing sides" do
      assert {:error, _} = Parser.parse("3d")
    end

    test "zero count" do
      assert {:error, _} = Parser.parse("0d6")
    end

    test "unknown keyword" do
      assert {:error, _} = Parser.parse("3d6foo")
    end

    test "trailing garbage" do
      assert {:error, _} = Parser.parse("3d6 abc")
    end
  end
end
