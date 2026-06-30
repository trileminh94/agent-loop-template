defmodule KimiCodeClone.MixProject do
  use Mix.Project

  def project do
    [
      app: :kimi_code_clone,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {KimiCodeClone.Application, []}
    ]
  end

  defp deps do
    [
      # Local path to the agent_loop library.
      {:agent_loop, path: "../.."},
      {:jason, "~> 1.4"}
    ]
  end
end
