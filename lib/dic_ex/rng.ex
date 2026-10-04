defmodule DicEx.RNG do
  @moduledoc """
  Pluggable randomness source for dice rolls.

  The default implementation (`DicEx.RNG.Default`) wraps `:rand`.
  `DicEx.RNG.Seeded` (what the `:seed` option uses) carries its own `:rand`
  state for reproducible sequences, and `DicEx.RNG.Entropy` draws from the OS
  CSPRNG. `DicEx.RNG.Deterministic` is a list-backed stub meant for tests — it
  pops pre-recorded outcomes in order, making modifier logic fully predictable.
  """

  @doc """
  Returns a pseudo-random integer in the inclusive range `1..sides`.
  """
  @callback roll(sides :: pos_integer()) :: pos_integer()
end
