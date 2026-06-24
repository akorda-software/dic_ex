# Changelog

All notable changes to dicEx are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
