<p align="center">
  <strong>dicEx</strong><br/>
  Pixel-art 3D dice roller for Phoenix LiveView
</p>

<p align="center">
  <a href="https://github.com/akorda-software/dic_ex/actions/workflows/ci.yml"><img src="https://github.com/akorda-software/dic_ex/actions/workflows/ci.yml/badge.svg" alt="CI"/></a>
  <a href="https://hex.pm/packages/dic_ex"><img src="https://img.shields.io/hexpm/v/dic_ex.svg" alt="Hex.pm"/></a>
  <a href="https://hexdocs.pm/dic_ex"><img src="https://img.shields.io/badge/documentation-gray" alt="Documentation"/></a>
  <a href="https://github.com/akorda-software/dic_ex/blob/main/LICENSE"><img src="https://img.shields.io/hexpm/l/dic_ex.svg" alt="License"/></a>
</p>

> D&D-style dice rolls in pure Elixir, with an optional Three.js + Rapier 3D
> visualization that drops into any LiveView.

`dicEx` computes dice rolls (advantage, drop/keep, explode, reroll) in Elixir so
modifiers always apply and results are seedable and testable. The tumbling dice
are theatre: the server decides, the dice land on what it decided.
The **core has zero runtime dependencies**; the LiveView component is opt-in.

The component supports these reveal modes:

- **2D engine** — the tumble lands on the value Elixir decided.
- **3D engine** (default) — dice tumble with real Rapier physics and settle on
  the faces Elixir decided. Dice the 3D engine can't show exactly (d100, d7…)
  are shown in 2D for that roll.
- **Physics-is-truth 3D** (opt-in, `physics={true}`) — dice land where Rapier
  takes them and the landed faces become the result. The browser decides the
  outcome, so a player can cheat; use it only where that is acceptable. It
  applies to d4/d6/d8/d10/d12/d20 pools without explode/reroll; other rolls
  stay server-decided.

## Features

- **Zero runtime dependencies** for the core — `phoenix_live_view` (+ `jason`) are
  optional and only needed for the component.
- **Full dice notation** — `3d6`, `2d20kh1` (advantage), `4d6dl1` (ability
  scores), `8d6!` (explode), `1d20r1` (reroll), `d%` (percentile), `1d20+5`.
- **Safe on untrusted input** — bounded dice count, sides and length;
  never-ending modifiers (`1d6r<=6`, `1d1!`) are rejected.
- **Deterministic & seedable** — replay rolls, anti-cheat, golden-path tests.
- **Structured results** — `%DicEx.Result{}` with per-die outcomes, kept/dropped
  flags, and a JSON-friendly `to_map/1` for LLM consumption.
- **3D pixel-art dice** — low-poly d4/d6/d8/d10/d12/d20 with procedurally drawn
  bitmap-font textures and real Rapier physics.
- **Drop-in LiveView component** — inline or modal, themed
  (`obsidian` / `arcane` / `dnd`).

## Installation

Add `dic_ex` to your `mix.exs`:

```elixir
defp deps do
  [
    {:dic_ex, "~> 0.3"}
  ]
end
```

Then:

```bash
mix deps.get
```

> **Try it in a Livebook** with no project at all — the core needs no Phoenix:
> ```elixir
> Mix.install([{:dic_ex, "~> 0.3"}])
> DicEx.roll("2d20kh1 + 5")
> ```

<!-- MDOC -->

## Quick start

```elixir
DicEx.roll("1d20")           # => %DicEx.Result{total: 14, ...}
DicEx.roll("3d6 + 2")        # => %DicEx.Result{total: 13, ...}
DicEx.roll("2d20kh1")        # advantage — keep highest
DicEx.roll("4d6dl1")         # 4d6, drop lowest
DicEx.roll("8d6!")           # explode (fireball)
DicEx.roll("1d20r1")         # reroll natural 1s

# safe variant for untrusted/LLM-generated expressions
{:ok, result} = DicEx.roll_e(prompted_by_the_llm)

# programmatic API matching a UI's "count + die + modifier"
DicEx.roll_dice(2, 20, mod: 5, advantage: true)

# reproducible
DicEx.roll("4d6", seed: 42)
```

### Notation reference

| Token      | Meaning                                            |
| ---------- | -------------------------------------------------- |
| `NdS`      | Roll `N` dice of `S` sides (`dS` = `1dS`)          |
| `d%`       | Percentile die (`d100`)                            |
| `kh[n]`    | Keep highest `n` (advantage)                       |
| `kl[n]`    | Keep lowest `n` (disadvantage)                     |
| `dh[n]`    | Drop highest `n`                                   |
| `dl[n]`    | Drop lowest `n`                                    |
| `!` / `!p` | Explode / explode & penetrate                      |
| `r<op>n`   | Reroll (`< <= = >= >`); `ro` rerolls once          |
| `+` / `-`  | Add / subtract pools or modifiers                  |

Only `+`/`-` compose — there's no `*`, `/`, or parentheses. A leading sign
applies to the first term (`-1d4+5`). One reroll modifier per pool.

### Limits

Expressions are bounded so untrusted input can't exhaust the process: at most
100 dice in total, 1000 sides per die and 256 characters. Override per call:

```elixir
DicEx.roll_e("150d6", max_dice: 200, max_sides: 1000, max_length: 256)
```

A repeating reroll that matches every face (`1d6r<=6`) and exploding a d1 are
rejected, since they would never finish.

### Reproducible rolls

Pass a seed for a reproducible sequence — useful for tests, replays, and
anti-cheat audits:

```elixir
DicEx.roll("2d20kh1", seed: 42)
```

The seeded state is private to the call (`DicEx.RNG.Seeded`); the calling
process's `:rand` state is left untouched.

<!-- MDOC -->

### Structured result

```elixir
%DicEx.Result{
  expression: "2d20kh1 + 5",
  total: 23,
  groups: [
    %{kind: :dice, notation: nil, sides: 20, subtotal: 18, modifiers: [{:keep_high, 1}],
      rolls: [%{value: 18, kept: true, exploded: false},
              %{value: 7,  kept: false, exploded: false}]},
    %{kind: :modifier, notation: nil, sides: nil, subtotal: 5, modifiers: [], rolls: []}
  ]
}

DicEx.Result.to_map(result)   # JSON-ready map for your LLM / client
```

The per-group `notation` is left `nil`; the full expression lives on the
top-level `expression` field.

## Phoenix LiveView component (optional)

The 3D dice are an opt-in layer on top of the pure-Elixir core. It needs
`phoenix_live_view` and `jason` (both `optional: true` in `dic_ex`), and ships
prebuilt assets you import into your bundle.

1. Import the assets (Phoenix 1.8+ only serves `app.js` / `app.css`, so dicEx is
   vendored, not referenced via external `<script>` tags):

   ```bash
   mix dic_ex.install   # copies the JS bundles -> assets/vendor, dic_ex.css -> assets/css
   ```

2. Wire the bundle:

   ```js
   // assets/js/app.js
   import "../vendor/dic_ex.min.js"        // sets window.DicExHooks (2D + 3D, ~2.7 MB)
   // or, if every roller uses engine="2d", the lightweight bundle:
   // import "../vendor/dic_ex_2d.min.js"  // 2D only, a few KB

   const hooks = { ...(window.DicExHooks || {}) }
   const liveSocket = new LiveSocket("/live", Socket, { hooks, /* ... */ })
   ```

   ```css
   /* assets/css/app.css — after the tailwind import */
   @import "./dic_ex.css";
   ```

3. Drop the component anywhere — inline or in a modal:

   ```heex
   <.live_component module={DicExWeb.DiceRoller} id="dice-roller" />
   ```

### Receiving rolls

Pass `on_roll: self()` and the host LiveView is notified with the full result,
ready to hand to an AI game master or any other consumer:

```elixir
<.live_component module={DicExWeb.DiceRoller} id="roller" on_roll={self()} />

def handle_info({:dic_ex_rolled, %{result: result, component: id}}, socket) do
  # result is a %DicEx.Result{} — feed its JSON map to the LLM
  {:noreply, socket}
end
```

### Host-owned results

To animate a result your own code already decided, push it to the roller's
hook directly (here the component's DOM id is `spell-stage`):

```elixir
push_event(socket, "dic_ex:roll:spell-stage", %{
  groups: [%{sides: 4, rolls: [%{value: 3, kept: true}]}], authoritative: true
})
```

`dic_ex:landed:spell-stage` then reports the supplied values; treat it as a
"settled" signal, never as a replacement for your committed result.
d4/d6/d8/d10/d12/d20 use 3D; other sides reveal the exact value in 2D for that
roll. `DicEx.renderer_capabilities/0` returns `%{authoritative_3d: true}` so
hosts can feature-detect it across versions.

### Component options

| Option            | Default      | Description                                                   |
| ----------------- | ------------ | ------------------------------------------------------------- |
| `:default`        | `"1d20"`     | Initial expression (re-applied only when it changes)          |
| `:theme`          | `"obsidian"` | `"obsidian"`, `"arcane"` or `"dnd"`, or a custom palette map  |
| `:engine`         | `"3d"`       | `"3d"` (Three.js + Rapier) or `"2d"` (canvas, no physics)     |
| `:physics`        | `false`      | `true` ⇒ 3D landed faces become the result (client-decided)   |
| `:rng`            | `nil`        | RNG module or `{module, state}`; `nil` ⇒ `DicEx.RNG.Default`  |
| `:limits`         | `[]`         | Parse limits: `max_dice`, `max_sides`, `max_length`           |
| `:labels`         | English      | `%{add:, clear:, roll:, rolling:, placeholder:, input:}`      |
| `:reveal_timeout` | `6000`       | ms before revealing if the dice never report settling         |
| `:on_roll`        | `nil`        | pid, name, `{name, node}`, `{:global, _}` or `{:via, _, _}`   |

For a Spanish UI, for example:

```heex
<.live_component module={DicExWeb.DiceRoller} id="roller"
  labels={%{add: "añadir", clear: "limpiar", roll: "Tirar", rolling: "tirando…",
            input: "Expresión de dados"}} />
```

## Building assets from source

The package ships prebuilt assets. To rebuild after editing `assets/src/`:

```bash
mix dic_ex.build        # -> priv/static/dic_ex.min.js and dic_ex_2d.min.js
mix dic_ex.test_assets  # Node's built-in lifecycle and face-orientation tests
```

Requires Node.js + a JS package manager (pnpm/bun/npm; the build task installs
deps automatically on first run). See [CONTRIBUTING.md](./CONTRIBUTING.md) for
the full development and release workflow.

The 3D hook recovers to 2D if scene initialization fails, releasing the WebGL
context and Rapier world it already owned; a queued roll keeps the server's
values. Hidden or zero-sized canvases pause, settled scenes stop their
animation loop, and a die that never comes to rest is locked after 4.5 s so a
roll always finishes.

## Architecture

```
dic_ex/
├── lib/dic_ex.ex                  # public API: roll/2, roll_dice/3, format/1
├── lib/dic_ex/                    # core: parser, roller, dice, result, rng
├── lib/dic_ex_web/                # LiveView component (guarded: needs LiveView)
├── lib/mix/tasks/                 # dic_ex.install (+ dev-only build, test_assets)
├── assets/src/                    # Three.js + Rapier scene, dice factory, hook
└── priv/static/                   # prebuilt dic_ex.min.js, dic_ex_2d.min.js, dic_ex.css
```

The roll is computed in Elixir for both engines. The component pushes the
result to its hook (`dic_ex:roll:<id>`, tagged with a nonce); the hook animates
it and reports back (`dic_ex:settled:<id>` / `dic_ex:landed:<id>`) so the result
is revealed in sync, with a server-side timer as a fallback. Reports from a
superseded roll are ignored. In physics mode the landed faces are validated
(count and range) and Elixir recomputes the result around them so keep/drop
still apply; invalid reports fall back to the server's own roll.

## Documentation

Full API docs are at [hexdocs.pm/dic_ex](https://hexdocs.pm/dic_ex).

## Contributing

Development setup, quality gates, and the release/publish workflow live in
[CONTRIBUTING.md](./CONTRIBUTING.md). Bug reports and pull requests are welcome
at [github.com/akorda-software/dic_ex](https://github.com/akorda-software/dic_ex).

## License

Copyright (c) 2026 kukapu. Released under the [MIT License](./LICENSE).
