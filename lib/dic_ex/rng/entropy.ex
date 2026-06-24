defmodule DicEx.RNG.Entropy do
  @moduledoc """
  Cryptographic high-entropy RNG. Every roll draws fresh entropy from the OS
  via `:crypto.strong_rand_bytes/1` — the BEAM's CSPRNG, the same source used
  for secrets — so outcomes are effectively unpredictable.

  `strong_rand_bytes` already mixes OS-level entropy (hardware timings, device
  jitter, RDRAND where available), which is strictly stronger than hand-mixing a
  clock value. Use this when you want honest, non-replayable rolls (a production
  demo, real games); use `DicEx.RNG.Default` when you need reproducibility via a
  fixed `:seed` (tests, replays, anti-cheat audits).

  Rolls are stateless and uniform over `1..sides`: rejection sampling removes
  the modulo bias a naive `rem/2` would introduce on the small dice ranges.

      DicEx.roll("2d20kh1", rng: DicEx.RNG.Entropy)
  """

  @behaviour DicEx.RNG

  # A 32-bit draw space keeps rejection waste negligible even for d100.
  @range 0x1_0000_0000

  @impl true
  def roll(sides) when is_integer(sides) and sides > 0 do
    # Largest multiple of `sides` that fits in the draw space. Values at or
    # above it are rejected and redrawn so every face gets exactly equal odds.
    limit = div(@range, sides) * sides

    @range
    |> Stream.unfold(fn _ -> {raw_uint32(), nil} end)
    |> Enum.find(fn n -> n < limit end)
    |> then(fn n -> rem(n, sides) + 1 end)
  end

  defp raw_uint32 do
    <<n::32>> = :crypto.strong_rand_bytes(4)
    n
  end
end
