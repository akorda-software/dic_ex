// Lightweight entry: only the 2D engine (no Three.js / Rapier). Bundles to
// priv/static/dic_ex_2d.min.js — a fraction of the full bundle's size — for
// apps that only use `engine="2d"`. Exposes the same `window.DicExHooks`.

import DiceRoller2DHook from "./hook_2d.js"

export const DiceRoller2D = DiceRoller2DHook

if (typeof window !== "undefined") {
  window.DicExHooks = window.DicExHooks || {}
  window.DicExHooks.DiceRoller2D = DiceRoller2DHook
}
