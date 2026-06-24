defmodule DicEx.RNG.Default do
  @moduledoc """
  The default RNG: a thin wrapper around Erlang's `:rand`.

  Every roll draws from `:rand.uniform/1`, so seeding the calling process (via
  `DicEx.roll/2`'s `:seed` option) yields a reproducible sequence. Use
  `DicEx.RNG.Entropy` when you want cryptographic, non-replayable randomness.
  """
  @behaviour DicEx.RNG

  @impl true
  def roll(sides) when is_integer(sides) and sides > 0 do
    :rand.uniform(sides)
  end
end

defmodule DicEx.RNG.Seeded do
  @moduledoc false
  @behaviour DicEx.RNG

  @impl true
  def roll(sides) when is_integer(sides) and sides > 0 do
    :rand.uniform(sides)
  end

  @doc """
  Seeds the global `:rand` state from an integer seed. Returns `:ok`.
  Use this to obtain a reproducible roll sequence with the default RNG.
  """
  def seed(seed) when is_integer(seed) do
    _ = :rand.seed(:exsss, seed)
    :ok
  end
end

defmodule DicEx.RNG.Deterministic do
  @moduledoc """
  A deterministic, list-backed RNG for tests.

  **Not for production.** It is not passed as a bare module — thread it as a
  `{DicEx.RNG.Deterministic, outcomes}` tuple so the roller can carry its state
  between rolls:

      DicEx.roll("3d6", rng: {DicEx.RNG.Deterministic, [4, 2, 6]})

  Outcomes are popped in order; once the list is exhausted, further rolls return
  `1`. Because every value is pinned, modifier logic (keep/drop, explode,
  reroll) becomes fully predictable — ideal for golden-path tests.
  """
  @behaviour DicEx.RNG

  @doc """
  Builds a deterministic RNG state from an ordered list of outcomes.
  """
  def new(outcomes) when is_list(outcomes) do
    {__MODULE__, outcomes}
  end

  @impl true
  def roll(_sides) do
    raise """
    DicEx.RNG.Deterministic must be threaded as a tuple, not called directly.
    Pass {DicEx.RNG.Deterministic, [outcomes]} as the :rng option.
    """
  end

  @doc false
  # Called by the roller with the carried state tuple. Returns {value, new_state}.
  def next({__MODULE__, [h | t]}), do: {h, {__MODULE__, t}}
  def next({__MODULE__, []}), do: {:exhausted, {__MODULE__, []}}
end
