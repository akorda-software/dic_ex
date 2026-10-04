defmodule DicEx.ThemeTest do
  use ExUnit.Case, async: true

  alias DicEx.Theme

  describe "resolve/1" do
    test "built-in name (atom or string) returns the full palette" do
      assert Theme.resolve(:obsidian) == Theme.defaults()
      assert Theme.resolve("arcane") |> Map.get(:accent) == "#6a4f2a"
      assert Theme.resolve("dnd") |> Map.get(:accent) == "#c7382b"
    end

    test "custom map with atom keys merges over the defaults" do
      palette = Theme.resolve(%{bg: "#ffffff"})
      assert palette.bg == "#ffffff"
      # untouched keys fall back to defaults
      assert palette.ink == Theme.defaults().ink
    end

    test "custom map with string keys is normalised, not silently dropped" do
      # regression: Map.merge over atom-keyed defaults used to keep the default
      # and discard the user's string-keyed value
      palette = Theme.resolve(%{"bg" => "#ffffff"})
      assert palette.bg == "#ffffff"
    end

    test "unknown string keys are ignored without creating atoms" do
      key = "dicex_unknown_#{System.unique_integer([:positive])}"
      palette = Theme.resolve(%{key => "#fff"})
      assert palette == Theme.defaults()
      assert_raise ArgumentError, fn -> String.to_existing_atom(key) end
    end

    test "values that could escape the style attribute are rejected" do
      for bad <- [
            "red; background: url(https://evil.test/x)",
            "url(//evil.test/x)",
            "#fff\" onmouseover=\"x",
            "red}",
            123
          ] do
        assert Theme.resolve(%{bg: bad}).bg == Theme.defaults().bg
      end
    end

    test "functional colour notations are accepted" do
      for ok <- ["rgba(1, 2, 3, 0.5)", "hsl(200deg 50% 40% / 80%)", "var(--brand)", "tomato"] do
        assert Theme.resolve(%{bg: ok}).bg == ok
      end
    end

    test "always returns a complete map" do
      for input <- [:obsidian, "arcane", %{accent: "#fff"}, %{"ink" => "#000"}] do
        assert Map.keys(Theme.resolve(input)) |> Enum.sort() ==
                 Map.keys(Theme.defaults()) |> Enum.sort()
      end
    end
  end

  describe "projections" do
    test "css_vars emits --dicex-* custom properties" do
      vars = Theme.css_vars(Theme.resolve(:obsidian))
      assert {"--dicex-bg", Theme.defaults().bg} in vars
      assert Enum.all?(vars, fn {k, _} -> String.starts_with?(k, "--dicex-") end)
    end

    test "canvas_palette uses camelCase string keys for the JS hooks" do
      palette = Theme.canvas_palette(Theme.resolve(:obsidian))
      assert palette["face"] == Theme.defaults().face
      assert palette["faceEdge"] == Theme.defaults().face_edge
    end

    test "builtins lists the shipped themes" do
      assert Theme.builtins() |> Enum.sort() == ["arcane", "dnd", "obsidian"]
    end
  end
end
