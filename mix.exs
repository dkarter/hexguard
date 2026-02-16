defmodule Hexguard.MixProject do
  use Mix.Project

  def project do
    [
      app: :hexguard,
      version: "0.2.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      description: "AI-assisted Hex dependency update automation for Mix projects",
      name: "Hexguard",
      source_url: "https://github.com/anomalyco/hexguard",
      homepage_url: "https://github.com/anomalyco/hexguard",
      docs: docs(),
      package: package(),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, "~> 1.0"},
      {:zoi, "~> 0.17"},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false},
      {:mimic, "~> 1.11", only: :test},
      {:igniter, "~> 0.7"}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "Source" => "https://github.com/anomalyco/hexguard"
      }
    ]
  end
end
