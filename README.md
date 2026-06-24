# dicEx

<p align="center"><strong>Pixel-art 3D dice roller for Phoenix LiveView</strong></p>

`dicEx` computes authoritative D&D-style dice rolls in pure Elixir and pairs
them with a Three.js + Rapier physics visualization that drops into any
LiveView as a component or modal. The roll is the source of truth (computed
server-side, seedable, testable); the tumbling dice are theatre and settle
naturally without a post-roll correction spin.

Built for **dragonEx** — an AI-driven D&D simulation — where the structured
`%DicEx.Result{}` feeds the game master LLM and the 3D view sells the moment.

## Features

- **Full dice notation** — `3d6`, `2d20kh1` (advantage), `4d6dl1` (ability
  scores), `8d6!` (explode), `1d20r1` (reroll), `1d20+5`.
- **Deterministic & seedable** — replay rolls, anti-cheat, golden-path tests.
- **Structured results** — `%DicEx.Result{}` with per-die outcomes, kept/dropped
  flags, and a JSON-friendly `to_map/1` for LLM consumption.
- **3D pixel-art dice** — low-poly d4/d6/d8/d10/d12/d20 with procedurally drawn
  bitmap-font textures and real Rapier physics.
- **Drop-in LiveView component** — inline or modal, themed (`obsidian` / `arcane`).
- **No web dependency required for the core** — `phoenix_live_view` is optional.

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
mix dic_ex.install   # copies dic_ex.min.js + dic_ex.css into priv/static
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
    %{kind: :dice, sides: 20, subtotal: 18, modifiers: [{:keep_high, 1}],
      rolls: [%{value: 18, kept: true}, %{value: 7, kept: false}]},
    %{kind: :modifier, subtotal: 5}
  ]
}

DicEx.Result.to_map(result)   # JSON-ready map for your LLM / client
```

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

### Receiving rolls (dragonEx integration)

Pass `on_roll: self()` and the host LiveView is notified with the full result,
ready to hand to the AI game master:

```elixir
<.live_component module={DicExWeb.DiceRoller} id="roller" on_roll={self()} />

def handle_info({:dic_ex_rolled, %{result: result}}, socket) do
  # result is a %DicEx.Result{} — feed its JSON map to the LLM
  DragonEx.GameMaster.register_roll(DicEx.Result.to_map(result))
  {:noreply, socket}
end
```

### Options

| Option      | Default     | Description                                            |
| ----------- | ----------- | ------------------------------------------------------ |
| `:default`  | `"1d20"`    | Initial expression                                      |
| `:theme`    | `"obsidian"`| `"obsidian"` or `"arcane"`                             |
| `:on_roll`  | `nil`       | `pid`/registered name to receive `{:dic_ex_rolled, _}` |
| `:autoplay` | `false`     | Roll once on mount                                      |

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

The roll is computed **before** any animation. The JS hook receives the result
via `push_event("dic_ex:roll", ...)`, starts the physical throw, and reveals the
server result once every visible die has settled.

## License

MIT
