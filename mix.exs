defmodule ExLibp2p.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/vidar/ex_libp2p"

  def project do
    [
      app: :ex_libp2p,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),

      # Docs
      name: "ExLibp2p",
      source_url: @source_url,
      docs: docs(),

      # Dialyzer
      dialyzer: [
        plt_add_apps: [:ex_unit]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {ExLibp2p.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:rustler, "~> 0.36.1", runtime: false},
      {:rustler_precompiled, "~> 0.8"},
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.3"},

      # Dev/Test
      {:ex_doc, "~> 0.36", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.2", only: :test}
    ]
  end

  defp aliases do
    [
      test: ["test --exclude integration"]
    ]
  end

  defp docs do
    [
      main: "ExLibp2p",
      extras: ["README.md"],
      source_ref: "v#{@version}"
    ]
  end
end
