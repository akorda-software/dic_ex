defmodule DicEx.Dice do
  @moduledoc """
  Supported die catalog and the canonical face layout per polyhedral type.

  The face layout is what the 3D renderer keys on: every die type maps its
  faces to a stable, ordered list so the client can orient the correct value
  up after the physics settle.
  """

  @supported [4, 6, 8, 10, 12, 20, 100]

  @doc """
  Returns the list of supported face counts: `~w(4 6 8 10 12 20 100)a` as integers.
  """
  def supported, do: @supported

  @doc """
  Validates that `sides` is one of the supported polyhedral dice.
  """
  def supported?(sides) when sides in @supported, do: true
  def supported?(_), do: false

  @doc """
  The ordered face list for a die. For standard dice the faces run `1..sides`.
  A d100 is modelled as a tens die (10, 20, ... 100) for display purposes, but
  rolling still uses the uniform `1..100` range.
  """
  def faces(100), do: Enum.map(10..100//10, & &1)
  def faces(sides), do: Enum.to_list(1..sides)

  @doc """
  Friendly name for a die, e.g. `20` -> `"d20"`.
  """
  def name(sides), do: "d#{sides}"
end
