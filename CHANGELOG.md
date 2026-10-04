# Changelog

All notable changes to dicEx are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Breaking
- The component is now **server-authoritative by default**: in 3D the dice
  tumble physically and settle on the faces Elixir rolled. The old
  physics-is-truth behaviour is opt-in via `physics={true}`; it only applies to
  d4/d6/d8/d10/d12/d20 pools without explode/reroll, and the landed values are
  validated (count and range) before use. Previously any client could submit
  arbitrary values, a physical d100 could only produce multiples of 10, other
  non-standard dice were biased, and explode/reroll results didn't match the
  dice on the table.
- Expressions are bounded: at most 100 dice, 1000 sides and 256 characters by
  default (override with `:max_dice`, `:max_sides`, `:max_length`).
  `1d6r<=6`-style repeating rerolls that match every face and exploding a d1
  are rejected; both used to hang the calling process.
- `1d6--5` / `1d6+-5` are now syntax errors; a sign is only allowed before the
  first term (`-1d4+5`, which now also works with a dice pool).
- Component UI strings default to English; pass `labels` to localise
  (e.g. `%{roll: "Tirar", clear: "limpiar", ...}`).
- `DicEx.Theme.resolve/1` ignores unknown keys and values that aren't plain CSS
  colours (no `;`, `url(...)`, quotes, ...), instead of creating atoms from them.

### Added
- `d%` percentile notation; `!P` is accepted like `!p`.
- Component options `physics`, `labels`, `limits` and `reveal_timeout`.
- Invalid expressions are shown in the component (`.dicex-error`).
- `on_roll` also accepts `{:global, name}` and `{:via, module, name}`.
- `priv/static/dic_ex_2d.min.js`: 2D-only bundle (~5 KB vs ~2.7 MB).
- `DicEx.renderer_capabilities/0` (`%{authoritative_3d: true}`) and
  `authoritative: true` roll payloads for host-pushed results.
- `DicEx.RNG.Seeded.new/1` for an explicit reproducible RNG state.
- `mix dic_ex.test_assets` and a CI job running it plus a bundle freshness
  check.

### Fixed
- The 6 s reveal fallback never fired (it was sent from a short-lived Task to
  itself), leaving the roller stuck on "rolling" if the dice never settled.
- Pressing "clear" during a 3D roll crashed the host LiveView.
- A typed expression wasn't stored, so the 3D reveal recomputed the previous
  expression and tray clicks appended to stale text.
- Settle/landed reports and fallback timers from a superseded roll are ignored
  (rolls carry a nonce).
- `:seed` no longer reseeds the calling process's global `:rand` state.
- `roll_e/2` returns `{:error, _}` for non-string input and for trailing
  operators such as `"5 !"` (both used to raise).
- A missing or malformed `on_roll` target is logged instead of crashing the
  reveal.
- A parent re-render no longer resets the expression to `default`.
- Tray buttons increment the trailing term (`1d6+1d8+1d6` → `…+2d6`) and ignore
  unknown values.
- Advantage and disadvantage together cancel out in `roll_dice/3`.
- One-off rolls of d100/d7/... show in 2D for that roll only; 3D resumes after.
- A 3D die that never comes to rest is locked after 4.5 s.
- 3D: preserve the latest roll during asynchronous initialization; recover to
  2D on initialization failure and release graphics/physics resources owned so
  far; stop frames when idle, hidden or zero-sized; free the Rapier world and
  WebGL context once on disposal.
- Requested-face orientation of inward-wound d10 geometry.
- `mix dic_ex.build` fails when bundling fails.
- Dev-only Mix tasks (`dic_ex.build`, `dic_ex.test_assets`) are no longer
  shipped in the Hex package.

## [0.2.0] - 2026-06-24

### Changed
- 3D dice now stop exactly where Rapier physics leaves them instead of rotating
  after settling to face the authoritative value.
- Removed the undocumented `!!` (compound explode) token: it parsed but behaved
  identically to `!`. Standard (`!`) and penetrate (`!p`) are unaffected.
- Documentation overhaul: README restructured to match common Hex package
  conventions; the `DicEx` module docs are now generated from it (single source).

### Fixed
- Multi-pool subtraction now applies its sign to every right-hand group and
  preserves group order for 3+ term expressions (e.g. `1d20+5-2`, `2d6-1d4`).
- `kept`/`dropped` flags are now correct for dice pools with duplicate values
  (e.g. `4d6dl1` on tied rolls) — `kept_values/1` and the render no longer
  undercount.
- 3D engine now disposes Three.js geometries, materials and textures on clear
  and teardown, fixing an unbounded GPU-memory leak across rolls.
- 3D hook no longer leaks retry timers while the physics scene initialises, and
  cancels pending work on `destroyed()`.
- `Theme.resolve/1` with a string-keyed map (e.g. from JSON) is now applied
  instead of silently falling back to the defaults.
- LiveView component: the reveal-fallback timer is now tagged per roll so it
  can't overwrite a later roll's result.
- Added `:crypto` to `extra_applications` (used by `DicEx.RNG.Entropy`).

## [0.1.0] - 2026-06-23

### Added
- Initial release.
- Core roller: `DicEx.roll/2`, `DicEx.roll_e/2`, `DicEx.roll_dice/3`, `DicEx.format/1`.
- Dice notation parser supporting `NdS`, `kh/kl/dh/dl`, explode (`!`, `!p`),
  reroll (`r`, `ro`, with comparators), and `+`/`-` expressions.
- Pluggable RNG (`DicEx.RNG`) with default `:rand`-backed and deterministic
  test stubs; `:seed` option for reproducible sequences.
- Structured `%DicEx.Result{}` with `to_map/1` and `kept_values/1`.
- `DicExWeb.DiceRoller` LiveView component (inline/modal, themed).
- Three.js + Rapier 3D visualization: low-poly pixel-art dice and physics tumble.
- `mix dic_ex.build` and `mix dic_ex.install` tasks.
