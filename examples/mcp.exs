# Run with: mix run examples/mcp.exs
#
# Shows how to connect to an MCP server and expose its tools to the loop.
# Requires an MCP stdio server such as the filesystem server:
#
#   npm install -g @modelcontextprotocol/server-filesystem
#
# Then set OPENAI_API_KEY and run:
#
#   mix run examples/mcp.exs

alias AgentLoop.MCP.Server
alias AgentLoop.ToolRegistry

Application.ensure_all_started(:agent_loop)

mcp_server = %Server{
  name: "filesystem",
  command: "npx",
  args: ["-y", "@modelcontextprotocol/server-filesystem", "."]
}

provider = %AgentLoop.Provider.OpenAICompatible{
  api_key: System.get_env("OPENAI_API_KEY"),
  base_url: "https://api.openai.com/v1"
}

registry = ToolRegistry.new()

config =
  AgentLoop.LoopConfig.new(provider, registry,
    model: "gpt-4o-mini",
    system_prompt: "You can use MCP tools. Prefer read_file and list_files from the filesystem server.",
    mcp_servers: [mcp_server]
  )

request = AgentLoop.RunRequest.new("List files in the current directory.")
result = AgentLoop.run(request, config)

IO.puts(result.content)
