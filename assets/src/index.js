// Entry point. Bundling this file produces priv/static/dic_ex.min.js which
// exposes the LiveView hooks as named exports on `window.DicExHooks`.
//
// Two render engines share the same Elixir contract (dic_ex:roll ->
// dic_ex:settled). Pick one per component via the `:engine` option
// ("3d" | "2d"); the LiveComponent mounts the matching hook name.
//
// In your app.js:
//   import { DiceRoller, DiceRoller2D } from "dic_ex"   // (if re-bundling)
//   // or, using the prebuilt bundle:
//   const hooks = {
//     DiceRoller:   window.DicExHooks.DiceRoller,    // 3D (Three.js + Rapier)
//     DiceRoller2D: window.DicExHooks.DiceRoller2D   // 2D (canvas, no physics)
//   }

import DiceRollerHook from "./hook.js"
import DiceRoller2DHook from "./hook_2d.js"

export const DiceRoller = DiceRollerHook
export const DiceRoller2D = DiceRoller2DHook

if (typeof window !== "undefined") {
  window.DicExHooks = window.DicExHooks || {}
  window.DicExHooks.DiceRoller = DiceRollerHook
  window.DicExHooks.DiceRoller2D = DiceRoller2DHook
}
