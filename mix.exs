defmodule DicEx.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/kukapu/dic_ex"
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
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      dialyzer: [
        ignore_warnings: ".dialyzer_ignore.exs",
        list_unused_filters: true
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

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
      files: ~w(lib priv/static mix.exs README.md LICENSE CHANGELOG.md),
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "DicEx",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md"]
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      build: ["dic_ex.build"],
      test: ["test"]
    ]
  end
end
