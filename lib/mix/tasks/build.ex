defmodule Mix.Tasks.DicEx.Build do
  @moduledoc """
  Builds the dicEx frontend assets (Three.js + Rapier) into
  `priv/static/dic_ex.min.js` so they ship with the Hex package.

      mix dic_ex.build

  Run inside the package when you change anything under `assets/src`. Consumers
  of the published package only need the prebuilt file plus the LiveView hook.

  ## Prerequisites

  Requires Node.js and runs `pnpm install` (or `npm install`) on first use when
  `assets/node_modules` is missing.
  """

  use Mix.Task

  @shortdoc "Builds the dicEx 3D frontend bundle"

  @impl true
  def run(_args) do
    assets_dir = Path.join(File.cwd!(), "assets")

    ensure_deps(assets_dir)
    ensure_priv_static()

    Mix.shell().info("[dicEx] bundling assets -> priv/static/dic_ex.min.js")

    {time, _} =
      :timer.tc(fn ->
        System.cmd("node", ["build.mjs"],
          cd: assets_dir,
          stderr_to_stdout: true,
          into: IO.binstream(:stdio, :line)
        )
      end)

    Mix.shell().info("[dicEx] built in #{div(time, 1000)}ms")
  end

  defp ensure_deps(assets_dir) do
    node_modules = Path.join(assets_dir, "node_modules")

    unless File.dir?(node_modules) do
      {runner, args} = package_manager()
      Mix.shell().info("[dicEx] installing JS deps with #{runner}")

      System.cmd(runner, args ++ ["install"],
        cd: assets_dir,
        stderr_to_stdout: true,
        into: IO.binstream(:stdio, :line)
      )
    end
  end

  defp ensure_priv_static do
    File.mkdir_p!(Path.join(File.cwd!(), "priv/static"))
  end

  defp package_manager do
    cond do
      System.find_executable("pnpm") -> {"pnpm", []}
      System.find_executable("bun") -> {"bun", ["install"]}
      System.find_executable("npm") -> {"npm", []}
      true -> Mix.raise("no JS package manager found (pnpm/npm/bun)")
    end
  end
end
