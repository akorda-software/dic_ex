defmodule DicEx.Dice do
  @moduledoc """
  Supported die catalog and the canonical face layout per polyhedral type.

  This is a public reference for host applications: validate player input
  against `supported?/1`, enumerate the catalog with `supported/0`, or look up
  a die's rendered face layout with `faces/1`. The 3D renderer itself reads its
  faces from the bundled JavaScript, so nothing in the BEAM calls these — they
  exist for consumers (e.g. to build a dice-tray UI or validate a chat command).

  The face layout maps each die type to a stable, ordered list so a client can
  orient the correct value up after the physics settle.
  """

  @supported [4, 6, 8, 10, 12, 20, 100]

  @doc """
  Returns the list of supported face counts.

      iex> DicEx.Dice.supported()
      [4, 6, 8, 10, 12, 20, 100]
  """
  def supported, do: @supported

  @doc """
  Validates that `sides` is one of the supported polyhedral dice.

      iex> DicEx.Dice.supported?(20)
      true
      iex> DicEx.Dice.supported?(7)
      false
  """
  def supported?(sides) when sides in @supported, do: true
  def supported?(_), do: false

  @doc """
  The ordered face list for a die. For standard dice the faces run `1..sides`.
  A d100 is modelled as a tens die (`10, 20, ... 100`) for display purposes;
  rolling still uses the uniform `1..100` range.

      iex> DicEx.Dice.faces(6)
      [1, 2, 3, 4, 5, 6]
      iex> DicEx.Dice.faces(100)
      [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
  """
  def faces(100), do: Enum.map(10..100//10, & &1)
  def faces(sides), do: Enum.to_list(1..sides)

  @doc """
  Friendly name for a die.

      iex> DicEx.Dice.name(20)
      "d20"
  """
  def name(sides), do: "d#{sides}"
end
