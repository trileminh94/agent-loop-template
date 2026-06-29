defmodule AgentLoop.MixProject do
  use Mix.Project

  def project do
    [
      app: :agent_loop,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env())
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
end
