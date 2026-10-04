// esbuild script: bundles the dicEx hooks into self-contained files:
//   priv/static/dic_ex.min.js     both engines (Three.js + Rapier, WASM inlined
//                                 so consumers don't serve a separate .wasm)
//   priv/static/dic_ex_2d.min.js  2D engine only, for apps that skip 3D
import * as esbuild from "esbuild"

const watch = process.argv.includes("--watch")

/** @type {import("esbuild").BuildOptions} */
const base = {
  bundle: true,
  format: "iife",
  target: ["es2020"],
  minify: !watch,
  sourcemap: watch,
  logLevel: "info",
  legalComments: "none",
  // Rapier compat build loads its WASM via base64 inline, so no loader needed.
  define: {
    "process.env.NODE_ENV": '"production"'
  }
}

const bundles = [
  { ...base, entryPoints: ["src/index.js"], outfile: "../priv/static/dic_ex.min.js" },
  { ...base, entryPoints: ["src/index_2d.js"], outfile: "../priv/static/dic_ex_2d.min.js" }
]

if (watch) {
  for (const options of bundles) await (await esbuild.context(options)).watch()
} else {
  await Promise.all(bundles.map((options) => esbuild.build(options)))
}
