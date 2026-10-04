defmodule DicEx.MixProject do
  use Mix.Project

  @version "0.3.0"
  @source_url "https://github.com/akorda-software/dic_ex"
  @description """
  Pixel-art 3D dice roller for Phoenix LiveView. Authoritative rolls in Elixir
  (D&D-style notation: NdS, advantage/disadvantage, drop/keep, explode) with an
  optional Three.js + Rapier physics visualization.
  """

  def project do
    [
      app: :dic_ex,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "dicEx",
      description: @description,
      package: package(),
      docs: docs(),
      source_url: @source_url,
      aliases: aliases(),
      dialyzer: [
        ignore_warnings: ".dialyzer_ignore.exs",
        list_unused_filters: true
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  defp deps do
    [
      {:phoenix_live_view, "~> 1.0", optional: true},
      {:phoenix_html, "~> 4.0", optional: true},
      {:jason, "~> 1.0", optional: true},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      name: "dic_ex",
      # The build/test_assets tasks need the package's own assets/ sources, so
      # they are kept out of the published package (only install ships).
      files: ~w(lib/dic_ex.ex lib/dic_ex lib/dic_ex_web lib/mix/tasks/install.ex
                priv/static mix.exs README.md LICENSE CHANGELOG.md),
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "DicEx",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md", "CONTRIBUTING.md", "LICENSE"]
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      build: ["dic_ex.build"]
    ]
  end
end
