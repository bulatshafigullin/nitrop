defmodule NITRO.Mixfile do
  use Mix.Project

  def project do
    [
      app: :nitro,
      version: "11.4.16",
      description: "NITRO Nitrogen Web Framework",
      package: package(),
      deps: deps(),
      erlc_options: [:nowarn_export_all, :nowarn_deprecated_function],
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [mod: {:nitro, []}]
  end

  def package do
    [
      files: ~w(include priv lib man src mix.exs rebar.config LICENSE README.md),
      licenses: ["ISC"],
      maintainers: ["Namdak Tonpa"],
      name: :nitro,
      links: %{"GitHub" => "https://github.com/synrc/nitro"}
    ]
  end

  def deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:n2o, "~> 13.4"},
      {:cowboy, "~> 2.10"},
      {:fs, "~> 11.4", only: :dev, runtime: false}
    ]
  end
end
