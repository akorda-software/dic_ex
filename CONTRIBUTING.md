# Contributing to dicEx

Development, quality, and release workflows for the `dic_ex` package. End users
only need the [README](./README.md); this file is for people working on the
package itself.

## Development setup

```bash
mix deps.get          # or: mix setup (alias)
mix compile
```

`mix.lock` is intentionally **not committed** — libraries don't ship lockfiles
(see `.gitignore`). Don't stage it in commits.

## Quality gates

Run all four before opening a PR or cutting a release:

```bash
mix format --check-formatted
mix credo
mix test
mix dialyzer      # type checks the @spec'd API (first run builds a PLT)
```

CI (`.github/workflows/ci.yml`) runs the same on every push and pull request:
formatting + credo on a single version, the test suite on an Elixir/OTP matrix,
and dialyzer.

Tests are deterministic by design: `async: true` everywhere, and randomness is
threaded as `{DicEx.RNG.Deterministic, [outcomes]}` or pinned with `seed:` — no
shared/global state.

## Working on the frontend assets

The 3D dice (Three.js + Rapier) live in `assets/src/` and ship as a prebuilt
`priv/static/dic_ex.min.js` (~2.7 MB) inside the Hex package. Rebuild it after
editing `assets/src/`:

```bash
mix dic_ex.build                 # alias: mix build  →  one-shot minified build
node assets/build.mjs --watch    # or: pnpm --dir assets watch  →  fast rebuilds on change
```

Gotchas:

- **The bundle is a committed artifact.** `priv/static/dic_ex.min.js` is *not*
  gitignored and is listed in `mix.exs` `package: files:`. Always rebuild and
  commit it; a stale bundle ships a stale UI.
- **The build only emits the JS.** `priv/static/dic_ex.css` is hand-authored and
  is never touched by esbuild — edit it directly.
- **`assets/js/` is vestigial and empty.** Real sources are `assets/src/`; the
  esbuild entry point is `assets/src/index.js` (sets `window.DicExHooks`).
- **~2.7 MB is expected.** Rapier's WASM is inlined as base64 so consumers serve
  a single file. Don't split it.
- **Package manager fallback is pnpm → bun → npm** (the build task auto-installs
  on first run). The project standard is **pnpm** (`assets/pnpm-lock.yaml`).

## Releases

A release is: version bump → changelog → quality gates → tag → Hex publish. The
version lives in three places that must agree — `mix.exs` (`@version`, line 4),
`CHANGELOG.md` (latest dated heading), and the git tag (`v<version>`).

1. **Bump `mix.exs`** — the `@version` module attribute only.
2. **Update `CHANGELOG.md`** (Keep a Changelog): promote the current
   `## [Unreleased]` block into a dated section
   (`## [x.y.z] - YYYY-MM-DD`, ISO date) and add a fresh empty
   `## [Unreleased]` above it. Keep only subsection headers that have entries.
3. **Verify consistency:**
   ```bash
   grep -m1 '@version' mix.exs
   grep -m1 '^## \[' CHANGELOG.md
   git tag --list 'v*'
   ```
4. **Quality gates** (see above) must pass.
5. **Rebuild assets** if `assets/src/` changed (see above), and commit the new
   `priv/static/dic_ex.min.js` into the release.
6. **Commit, tag, push.** Commit style is lowercase imperative; the tag is
   `v<version>` because `mix.exs` sets `source_ref: "v#{@version}"`:
   ```bash
   git add mix.exs CHANGELOG.md priv/static/dic_ex.min.js
   git commit -m "release: vx.y.z"
   git tag vx.y.z
   git push && git push --tags
   ```
7. **Publish to Hex** (first time: `mix hex.user auth`):
   ```bash
   mix hex.build      # inspect the file list; dic_ex-<version>.tar is gitignored
   mix hex.publish    # re-builds and uploads
   mix hex.info dic_ex
   ```

Release gotchas:

- **A Hex version, once published, is immutable** — Hex rejects re-publishing the
  same `<package>-<version>`. Verify the version and tarball contents with
  `mix hex.build` before confirming `mix hex.publish`.
- **Tag format is `v<version>`**, not bare `0.2.0`. A bare/missing tag breaks
  ex_doc source links.
- **Pre-1.0 SemVer:** while at `0.x`, breaking changes are allowed in a MINOR
  bump. After 1.0, follow strict SemVer.
- **Optional deps stay optional.** `phoenix_live_view` / `phoenix_html` /
  `jason` are `optional: true`; don't make them hard deps. The web component is
  conditionally compiled (`Code.ensure_loaded?`), so the core compiles with no
  web deps.
- **`MIX_ENV` doesn't matter for library publishing** — there's no `mix release`
  here.

## Conventions

- **Namespaces:** `DicEx` (core) and `DicExWeb` (optional web layer); mix tasks
  under `Mix.Tasks.DicEx.*`. One module per file.
- **Internal modules** carry `@moduledoc false`; public modules document `iex>`
  examples (doctest-ready) and `@spec`s.
- **RNG is a behaviour** (`DicEx.RNG`) threaded explicitly through evaluation for
  reproducibility — never call `:rand` ad hoc inside the pipeline.
- **Commits:** lowercase imperative summary (`docs: ...`, `release: ...`).
