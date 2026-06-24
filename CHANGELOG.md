# Changelog

All notable changes to dicEx are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- 3D dice now stop exactly where Rapier physics leaves them instead of rotating
  after settling to face the authoritative value.

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
