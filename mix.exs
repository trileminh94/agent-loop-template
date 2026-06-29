defmodule AgentLoop.MixProject do
  use Mix.Project

  @source_url "https://github.com/trileminh94/agent-loop-template"

  def project do
    [
      app: :agent_loop,
      version: "0.2.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      description: description(),
      package: package(),
      name: "AgentLoop",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :req]
    ]
  end

  defp deps do
    [
      # Example provider uses Req for HTTP calls.
      # Consumers can replace this with Finch or another client.
      {:req, "~> 0.5.0"},

      # Persistence adapter default.
      {:exqlite, "~> 0.23"},

      # Dev/test
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description do
    "A minimal, reusable think → act → observe agent loop for Elixir, " <>
      "with workspace tools, OpenAI/DeepSeek providers, and optional SQLite persistence."
  end

  defp package do
    [
      name: "agent_loop",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "AgentLoop",
      extras: ["README.md"]
    ]
  end
end
