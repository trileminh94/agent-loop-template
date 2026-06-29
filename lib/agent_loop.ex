defmodule AgentLoop do
  @moduledoc """
  Public API for the agent loop template.

  ## Quick start

      registry =
        AgentLoop.ToolRegistry.new()
        |> AgentLoop.ToolRegistry.register_many([
          AgentLoop.Tools.Echo,
          AgentLoop.Tools.ReadFile
        ])

      provider = %AgentLoop.Provider.OpenAICompatible{
        api_key: System.get_env("OPENAI_API_KEY"),
        base_url: "https://api.openai.com/v1",
        http_options: [receive_timeout: 60_000]
      }

      config =
        AgentLoop.LoopConfig.new(provider, registry,
          model: "gpt-4o-mini",
          system_prompt: "You are a helpful coding assistant.",
          max_iterations: 10
        )

      request = AgentLoop.RunRequest.new("Read the README and summarize it.")

      result = AgentLoop.run(request, config)
      IO.puts(result.content)

  ## Streaming events

  Pass an `:event_callback` to observe the loop:

      config = AgentLoop.LoopConfig.new(provider, registry,
        event_callback: fn event ->
          IO.inspect(event, label: "agent event")
        end
      )

  ## Persistence

  Provide a `persistence` tuple to resume sessions, recall memory, and store
  execution traces:

      {:ok, persistence} = AgentLoop.Persistence.new(AgentLoop.Persistence.SQLite, database: "data.db")

      config = AgentLoop.LoopConfig.new(provider, registry,
        persistence: persistence,
        trace: true
      )

      request = AgentLoop.RunRequest.new("continue our work", session_id: "project-alpha")
      result = AgentLoop.run(request, config)
  """

  alias AgentLoop.Loop
  alias AgentLoop.LoopConfig
  alias AgentLoop.RunRequest
  alias AgentLoop.RunResult

  @doc "Run the agent loop synchronously and return a `RunResult`."
  @spec run(RunRequest.t(), LoopConfig.t()) :: RunResult.t()
  def run(%RunRequest{} = request, %LoopConfig{} = config) do
    Loop.run(request, config)
  end

  @doc """
  Run the agent loop with an event callback for streaming updates.

  This is a convenience wrapper around `run/2` that injects an event callback.
  """
  @spec run(RunRequest.t(), LoopConfig.t(), (AgentLoop.Event.t() -> any())) :: RunResult.t()
  def run(%RunRequest{} = request, %LoopConfig{} = config, callback)
      when is_function(callback, 1) do
    Loop.run(request, %{config | event_callback: callback})
  end
end
