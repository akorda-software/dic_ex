// esbuild script: bundles the dicEx hook into a single self-contained file
// at priv/static/dic_ex.min.js. Rapier's WASM is inlined so consumers don't
// need to serve a separate .wasm asset.
import * as esbuild from "esbuild"

const watch = process.argv.includes("--watch")

/** @type {import("esbuild").BuildOptions} */
const options = {
  entryPoints: ["src/index.js"],
  bundle: true,
  format: "iife",
  target: ["es2020"],
  minify: !watch,
  sourcemap: watch,
  outfile: "../priv/static/dic_ex.min.js",
  logLevel: "info",
  legalComments: "none",
  // Rapier compat build loads its WASM via base64 inline, so no loader needed.
  define: {
    "process.env.NODE_ENV": '"production"'
  }
}

if (watch) {
  const ctx = await esbuild.context(options)
  await ctx.watch()
} else {
  await esbuild.build(options)
}
