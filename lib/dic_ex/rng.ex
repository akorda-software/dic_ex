defmodule DicEx.RNG do
  @moduledoc """
  Pluggable randomness source for dice rolls.

  The default implementation (`DicEx.RNG.Default`) wraps `:rand` so the whole
  tree can be seeded for reproducible sequences. `DicEx.RNG.Deterministic` is a
  list-backed stub meant exclusively for tests — it pops pre-recorded outcomes
  in order, making modifier logic fully predictable.
  """

  @doc """
  Returns a pseudo-random integer in the inclusive range `1..sides`.
  """
  @callback roll(sides :: pos_integer()) :: pos_integer()
end
