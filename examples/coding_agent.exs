# Run with: mix run examples/coding_agent.exs
#
# A local coding assistant that can read, search, and edit files.
# Needs OPENAI_API_KEY or DEEPSEEK_API_KEY.

alias AgentLoop.ToolRegistry
alias AgentLoop.Tools.EditFile
alias AgentLoop.Tools.FetchURL
alias AgentLoop.Tools.Grep
alias AgentLoop.Tools.ListFiles
alias AgentLoop.Tools.Memory
alias AgentLoop.Tools.ReadFile
alias AgentLoop.Tools.ShellExec
alias AgentLoop.Tools.WriteFile
alias AgentLoop.Tools.Workspace

Application.ensure_all_started(:agent_loop)

Workspace.configure(root: ".", restrict: true)

provider = %AgentLoop.Provider.OpenAICompatible{
  api_key: System.get_env("OPENAI_API_KEY"),
  base_url: "https://api.openai.com/v1"
}

registry =
  ToolRegistry.new()
  |> ToolRegistry.register_many([
    ReadFile,
    ListFiles,
    WriteFile,
    EditFile,
    Grep,
    ShellExec,
    FetchURL,
    Memory
  ])

config =
  AgentLoop.LoopConfig.new(provider, registry,
    model: "gpt-4o-mini",
    system_prompt: "You are a helpful coding assistant. Use tools when needed.",
    event_callback: fn event ->
      IO.inspect(event.type, label: "event")
    end
  )

request = AgentLoop.RunRequest.new("List the files in this project and summarize it.")
result = AgentLoop.run(request, config)

IO.puts("\n---")
IO.puts(result.content)
