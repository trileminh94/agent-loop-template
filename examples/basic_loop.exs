# Run with: mix run examples/basic_loop.exs
#
# Needs OPENAI_API_KEY in the environment.

alias AgentLoop.ToolRegistry
alias AgentLoop.Tools.Echo

Application.ensure_all_started(:agent_loop)

provider = %AgentLoop.Provider.OpenAICompatible{
  api_key: System.get_env("OPENAI_API_KEY"),
  base_url: "https://api.openai.com/v1"
}

registry =
  ToolRegistry.new()
  |> ToolRegistry.register(Echo)

config =
  AgentLoop.LoopConfig.new(provider, registry,
    model: "gpt-4o-mini",
    system_prompt: "You are a helpful assistant."
  )

request = AgentLoop.RunRequest.new("Say hello using the echo tool.")
result = AgentLoop.run(request, config)

IO.puts(result.content)
