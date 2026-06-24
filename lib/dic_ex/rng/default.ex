defmodule DicEx.RNG.Default do
  @moduledoc false
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
  @moduledoc false
  # Internal: do not use in production. Rolls are served from a fixed list so
  # tests can assert exact modifier behaviour.
  @behaviour DicEx.RNG

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
