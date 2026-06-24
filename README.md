# dicEx

<p align="center"><strong>Pixel-art 3D dice roller for Phoenix LiveView</strong></p>

`dicEx` computes D&D-style dice rolls in pure Elixir and pairs them with a
Three.js + Rapier physics visualization that drops into any LiveView as a
component or modal. The rolls are seedable and testable; the tumbling dice are
theatre that settle naturally without a post-roll correction spin.

Two reveal modes, both computed through Elixir so modifiers always apply:

- **2D engine** — the server roll is the source of truth; the visible tumble
  lands exactly on the value Elixir decided.
- **3D engine** — *physics is truth*: the dice land where Rapier takes them and
  the landed faces are reported back, so what you see is what happened.

## Features

- **Full dice notation** — `3d6`, `2d20kh1` (advantage), `4d6dl1` (ability
  scores), `8d6!` (explode), `1d20r1` (reroll), `1d20+5`.
- **Deterministic & seedable** — replay rolls, anti-cheat, golden-path tests.
- **Structured results** — `%DicEx.Result{}` with per-die outcomes, kept/dropped
  flags, and a JSON-friendly `to_map/1` for LLM consumption.
- **3D pixel-art dice** — low-poly d4/d6/d8/d10/d12/d20 with procedurally drawn
  bitmap-font textures and real Rapier physics.
- **Drop-in LiveView component** — inline or modal, themed (`obsidian` / `arcane` / `dnd`).
- **No web dependency required for the core** — `phoenix_live_view` (+ `jason`)
  are optional; only needed for the component.

## Installation

Add `dic_ex` to your `mix.exs`:

```elixir
def deps do
  [
    {:dic_ex, "~> 0.1.0"}
  ]
end
```

Then:

```bash
mix deps.get
mix dic_ex.install   # copies dic_ex.min.js -> assets/vendor, dic_ex.css -> assets/css
```

## Core usage (pure Elixir)

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

### Structured result

```elixir
%DicEx.Result{
  expression: "2d20kh1 + 5",
  total: 23,
  groups: [
    %{kind: :dice, notation: nil, sides: 20, subtotal: 18, modifiers: [{:keep_high, 1}],
      rolls: [%{value: 18, kept: true, exploded: false}, %{value: 7, kept: false, exploded: false}]},
    %{kind: :modifier, notation: nil, sides: nil, subtotal: 5, modifiers: [], rolls: []}
  ]
}

DicEx.Result.to_map(result)   # JSON-ready map for your LLM / client
```

The per-group `notation` is left `nil`; the full expression lives on the
top-level `expression` field.

### Notation reference

| Token       | Meaning                                       |
| ----------- | --------------------------------------------- |
| `NdS`       | Roll `N` dice of `S` sides (d4..d100)         |
| `kh[n]`     | Keep highest `n` (advantage)                  |
| `kl[n]`     | Keep lowest `n` (disadvantage)                |
| `dh[n]`     | Drop highest `n`                              |
| `dl[n]`     | Drop lowest `n`                               |
| `!` / `!p`  | Explode / explode & penetrate                 |
| `r<op>n`    | Reroll (`< <= = >= >`); `ro` rerolls once      |
| `+` / `-`   | Add / subtract pools or modifiers             |

## LiveView component

1. Import the assets into your bundle (Phoenix 1.8+ only serves `app.js` /
   `app.css`, so dicEx ships as vendored imports, not external tags):

```js
// assets/js/app.js
import "../vendor/dic_ex.min.js"        // sets window.DicExHooks

const hooks = { ...(window.DicExHooks || {}) }
const liveSocket = new LiveSocket("/live", Socket, { hooks, /* ... */ })
```

```css
/* assets/css/app.css — after the tailwind import */
@import "./dic_ex.css";
```

`mix dic_ex.install` copies `dic_ex.min.js` → `assets/vendor/` and
`dic_ex.css` → `assets/css/` and prints the exact wiring.

2. Drop the component anywhere — inline or in a modal:

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

### Options

| Option     | Default      | Description                                              |
| ---------- | ------------ | -------------------------------------------------------- |
| `:default` | `"1d20"`     | Initial expression                                        |
| `:theme`   | `"obsidian"` | `"obsidian"`, `"arcane"` or `"dnd"`, or a custom palette |
| `:engine`  | `"3d"`       | `"3d"` (Three.js + Rapier) or `"2d"` (canvas, no physics) |
| `:rng`     | `nil`        | RNG module; `nil` ⇒ `DicEx.RNG.Default` (seedable)        |
| `:on_roll` | `nil`        | `pid` / registered name to receive `{:dic_ex_rolled, _}`   |

## Building assets from source

The package ships prebuilt assets. To rebuild after editing `assets/src`:

```bash
mix dic_ex.build     # bundles Three.js + Rapier -> priv/static/dic_ex.min.js
```

Requires Node.js + a JS package manager (pnpm/bun/npm; the build task installs
deps automatically on first run).

## Architecture

```
dic_ex/
├── lib/dic_ex.ex                  # public API: roll/2, roll_dice/3, format/1
├── lib/dic_ex/                    # core: parser, roller, dice, result, rng
├── lib/dic_ex_web/                # LiveView component (guarded: needs LiveView)
├── lib/mix/tasks/                 # mix dic_ex.build, mix dic_ex.install
├── assets/src/                    # Three.js + Rapier scene, dice factory, hook
└── priv/static/                   # prebuilt dic_ex.min.js + dic_ex.css
```

The roll is computed through Elixir for both engines. The 2D hook receives the
server result via `push_event("dic_ex:roll", ...)`, tumbles the dice, and reveals
it in sync. The 3D hook throws the dice physically and, once they settle,
reports the landed faces back (`dic_ex:landed`) so Elixir recomputes the result
around the physics outcome — modifiers (kh/dl/explode…) still apply, and the
revealed total matches exactly what landed on the table.

## License

MIT
