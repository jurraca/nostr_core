defmodule NostrCore.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/jurraca/nostr_core"

  def project do
    [
      app: :nostr_core,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :test,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:lib_secp256k1, "~> 0.7"},
      {:bechamel, "~> 1.1"},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp description() do
    "Minimal Elixir library for the Nostr protocol — events, tags, filters, messages, and cryptography."
  end

  defp package do
    [
      name: "nostr_core",
      maintainers: ["jurraca <julienu@pm.me>"],
      files: ~w(lib .formatter.exs mix.exs README* LICENSE* CHANGELOG*),
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      api_reference: false,
      extras: ["README.md"],
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
