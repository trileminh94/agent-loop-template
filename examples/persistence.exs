# Run with: mix run examples/persistence.exs
#
# Shows how to resume a session and persist traces.

alias AgentLoop.Persistence
alias AgentLoop.ToolRegistry
alias AgentLoop.Tools.Echo

Application.ensure_all_started(:agent_loop)

provider = %AgentLoop.Provider.OpenAICompatible{
  api_key: System.get_env("OPENAI_API_KEY"),
  base_url: "https://api.openai.com/v1"
}

{:ok, persistence} =
  Persistence.new(AgentLoop.Persistence.SQLite, database: ".agent_loop/demo.db")

registry =
  ToolRegistry.new()
  |> ToolRegistry.register(Echo)

config =
  AgentLoop.LoopConfig.new(provider, registry,
    model: "gpt-4o-mini",
    persistence: persistence,
    trace: true
  )

# First run.
request1 = AgentLoop.RunRequest.new("Remember that we are building an Elixir agent.", session_id: "demo")
result1 = AgentLoop.run(request1, config)
IO.puts("Run 1: #{result1.content}")

# Later, resume the same session.
request2 = AgentLoop.RunRequest.new("What did I ask you to remember?", session_id: "demo")
result2 = AgentLoop.run(request2, config)
IO.puts("Run 2: #{result2.content}")

# Inspect the trace for the most recent run.
{adapter, state} = persistence
{:ok, traces} = adapter.get_trace(state, "demo", request2.run_id)
IO.puts("\nTrace events: #{length(traces)}")
