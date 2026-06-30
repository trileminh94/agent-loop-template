# Agent Loop Template

A minimal, reusable **think → act → observe** agent loop in Elixir.

This template is designed to be copied into another project and extended with your own providers, tools, and persistence layer. It is intentionally small: no GenServer, no channels, no multi-tenancy. It ships with a functional agent loop, workspace-aware coding tools, OpenAI and DeepSeek providers, and optional SQLite persistence.

## Installation

Add `agent_loop` to your `mix.exs`:

```elixir
def deps do
  [
    {:agent_loop, "~> 0.2.0"}
  ]
end
```

Then run:

```bash
mix deps.get
```

## What it does

1. Takes a user message and conversation history.
2. Builds the list of available tools.
3. Sends `messages + tools` to an LLM provider.
4. If the LLM returns tool calls, executes them (in parallel when there are multiple).
5. Appends the results and repeats up to `max_iterations`.
6. Returns the final content, full message history, and metadata.

## Project structure

```
lib/
├── agent_loop.ex                         # Public API
├── mix/tasks/agent.run.ex                # CLI entry point
└── agent_loop/
    ├── loop.ex                           # Core think → act → observe loop
    ├── message.ex                        # Message struct
    ├── tool.ex                           # Tool behaviour
    ├── tool_call.ex                      # ToolCall struct
    ├── tool_result.ex                    # ToolResult struct
    ├── tool_definition.ex                # Schema sent to LLM
    ├── tool_registry.ex                  # Tool registration/execution
    ├── provider.ex                       # Provider behaviour
    ├── provider/
    │   ├── openai_compatible.ex          # OpenAI-compatible provider
    │   └── deepseek.ex                   # DeepSeek provider
    ├── persistence.ex                    # Persistence behaviour
    ├── mcp/                              # MCP client and bridge
    │   ├── client.ex                     # Stdio JSON-RPC client
    │   ├── messages.ex                   # JSON-RPC builders
    │   ├── server.ex                     # MCP server config
    │   └── tool_bridge.ex                # MCP -> AgentLoop tool mapping
    ├── persistence/
    │   ├── no_op.ex                      # No-op default adapter
    │   ├── sqlite.ex                     # SQLite-backed adapter
    │   └── migrations/
    │       └── 001_initial.ex            # Schema migration
    ├── run_request.ex                    # Input struct
    ├── run_result.ex                     # Output struct
    ├── loop_config.ex                    # Loop configuration
    ├── loop_state.ex                     # Internal loop state
    ├── event.ex                          # Event struct
    └── tools/
        ├── workspace.ex                  # Workspace resolution/safety
        ├── echo.ex                       # Example tool
        ├── read_file.ex                  # Read files with line ranges
        ├── list_files.ex                 # List directories
        ├── write_file.ex                 # Write/append files
        ├── edit_file.ex                  # Search-and-replace edits
        ├── grep.ex                       # Search file contents
        ├── shell_exec.ex                 # Run shell commands
        ├── fetch_url.ex                  # Fetch web pages
        ├── memory.ex                     # Persistent notes
        └── context.ex                    # Per-tool execution context
```

## Quick start

```elixir
# 1. Build a tool registry
registry =
  AgentLoop.ToolRegistry.new()
  |> AgentLoop.ToolRegistry.register_many([
    AgentLoop.Tools.Echo,
    AgentLoop.Tools.ReadFile
  ])

# 2. Configure a provider
provider = %AgentLoop.Provider.OpenAICompatible{
  api_key: System.get_env("OPENAI_API_KEY"),
  base_url: "https://api.openai.com/v1"
}

# 3. Configure the loop
config =
  AgentLoop.LoopConfig.new(provider, registry,
    model: "gpt-4o-mini",
    system_prompt: "You are a helpful coding assistant.",
    max_iterations: 10
  )

# 4. Run it
request = AgentLoop.RunRequest.new("Read README.md and summarize it.")
result = AgentLoop.run(request, config)

IO.puts(result.content)
```

## Adding a custom tool

Create a module that implements `AgentLoop.Tool`:

```elixir
defmodule MyApp.Tools.Calculator do
  @behaviour AgentLoop.Tool

  @impl true
  def name, do: "calculate"

  @impl true
  def description, do: "Evaluate a basic math expression."

  @impl true
  def parameters do
    %{
      "type" => "object",
      "properties" => %{
        "expression" => %{
          "type" => "string",
          "description" => "Math expression like '2 + 2'"
        }
      },
      "required" => ["expression"]
    }
  end

  @impl true
  def execute(%{"expression" => expr}) do
    case Code.eval_string(expr) do
      {result, _} -> {:ok, to_string(result)}
      _ -> {:error, "invalid expression"}
    end
  end
end
```

Register it:

```elixir
registry = AgentLoop.ToolRegistry.new() |> AgentLoop.ToolRegistry.register(MyApp.Tools.Calculator)
```

## Adding a custom provider

Implement the `AgentLoop.Provider` behaviour. The loop passes a normalized
`AgentLoop.Provider.Schema.Request` and expects an
`AgentLoop.Provider.Schema.Response`:

```elixir
defmodule MyApp.Providers.MyProvider do
  @behaviour AgentLoop.Provider

  alias AgentLoop.Provider.Schema

  @impl true
  def chat(provider, %Schema.Request{} = request) do
    # Convert request to your provider's API format, call the API, then
    # return {:ok, %Schema.Response{content: "...", tool_calls: [...]}} |
    #        {:error, reason}
  end
end
```

## Streaming events

Pass an event callback to observe the loop:

```elixir
config = AgentLoop.LoopConfig.new(provider, registry,
  event_callback: fn event ->
    case event.type do
      :thinking -> IO.puts("Thinking...")
      :tool_call -> IO.inspect(event.payload, label: "tool call")
      :tool_result -> IO.inspect(event.payload, label: "tool result")
      :run_completed -> IO.puts("Done")
      _ -> :ok
    end
  end
)
```

Events emitted:

| Event | Payload |
|---|---|
| `:run_started` | `%{message: ...}` |
| `:thinking` | `%{iteration: ...}` |
| `:tool_call` | `%{id, name, arguments}` |
| `:tool_calls` | `%{count, names}` |
| `:tool_result` | `%{id, name, content, is_error}` |
| `:run_completed` | `%{content, iterations, total_tool_calls, finish_reason}` |

## Coding agent tools

This template ships with a practical, workspace-aware toolset inspired by goclaw's native tools:

| Tool | Purpose |
|------|---------|
| `read_file` | Read files, with optional line ranges |
| `list_files` | List directory contents |
| `write_file` | Write or append files, creating parent directories |
| `edit_file` | Replace exact text without rewriting whole files |
| `grep` | Search file contents (uses ripgrep when available) |
| `shell_exec` | Run commands inside the workspace |
| `fetch_url` | Fetch web pages as readable text |
| `memory` | Remember and recall notes across runs |

All filesystem tools resolve relative paths against a workspace root and can be restricted to that root.

### CLI usage

Run the agent from the command line:

```bash
export OPENAI_API_KEY=sk-...
mix agent.run "read lib/agent_loop.ex and summarize it"
```

Target a specific workspace:

```bash
mix agent.run "list all elixir files" --workspace ./my_project
```

Use DeepSeek:

```bash
export DEEPSEEK_API_KEY=sk-...
mix agent.run "explain the README" --provider deepseek
```

Point to another OpenAI-compatible provider:

```bash
mix agent.run "hello" --base-url https://api.openrouter.ai/api/v1 --model openai/gpt-4o-mini
```

### Using the tools in code

```elixir
AgentLoop.Tools.Workspace.configure(root: "/path/to/project", restrict: true)

registry =
  AgentLoop.ToolRegistry.new()
  |> AgentLoop.ToolRegistry.register_many([
    AgentLoop.Tools.ReadFile,
    AgentLoop.Tools.ListFiles,
    AgentLoop.Tools.WriteFile,
    AgentLoop.Tools.EditFile,
    AgentLoop.Tools.Grep,
    AgentLoop.Tools.ShellExec,
    AgentLoop.Tools.FetchURL,
    AgentLoop.Tools.Memory
  ])

config = AgentLoop.LoopConfig.new(provider, registry, system_prompt: "You are a coding assistant.")
result = AgentLoop.run(AgentLoop.RunRequest.new("find all TODOs"), config)
```

## Persistence

The loop now supports optional persistence through the `AgentLoop.Persistence` behaviour. A SQLite adapter is included.

Persisted data:

- **Sessions** — conversation history that can be resumed
- **Memory** — notes remembered by the `memory` tool
- **Traces** — step-by-step record of a run

### CLI usage

Resume a session:

```bash
mix agent.run "what did we discuss?" --session my-session
```

Enable traces:

```bash
mix agent.run "find TODOs" --session my-session --trace
```

Use a custom database path:

```bash
mix agent.run "hello" --session my-session --memory-db ./data/agent.db
```

### In code

```elixir
{:ok, persistence} = AgentLoop.Persistence.new(AgentLoop.Persistence.SQLite, database: "data.db")

config = AgentLoop.LoopConfig.new(provider, registry,
  persistence: persistence,
  trace: true
)

request = AgentLoop.RunRequest.new("continue our work", session_id: "project-alpha")
result = AgentLoop.run(request, config)
```

### Custom adapters

Implement the `AgentLoop.Persistence` behaviour and pass the `{Adapter, state}` tuple to `LoopConfig.new/3`.

## Streaming

Enable streaming to receive content and tool-call deltas as they arrive:

```elixir
config = AgentLoop.LoopConfig.new(provider, registry,
  model: "gpt-4o-mini",
  stream: true,
  event_callback: fn event ->
    case event.type do
      :content_delta -> IO.write(event.payload.content)
      :tool_call_name -> IO.inspect(event.payload, label: "tool")
      _ -> :ok
    end
  end
)
```

The provider must implement `AgentLoop.Provider.chat_stream/3`. The loop falls back to `chat/2` for providers that do not.

## Retry policy

Configure retries for transient provider errors:

```elixir
config = AgentLoop.LoopConfig.new(provider, registry,
  max_retries: 3,
  retry_backoff_ms: 500,
  retry_on: fn reason -> match?(%{status: status} when status in 500..599, reason) end
)
```

## Context-window truncation

On context-length errors, the loop can drop older messages and retry:

```elixir
config = AgentLoop.LoopConfig.new(provider, registry,
  truncation_strategy: :drop_oldest,
  max_truncation_retries: 1
)
```

## Structured output

Parse and validate JSON responses:

```elixir
result = AgentLoop.run(request, config)

validator = fn data ->
  if is_map(data) and is_integer(data["answer"]),
    do: {:ok, data},
    else: {:error, :invalid_shape}
end

{:ok, parsed} = AgentLoop.StructuredOutput.parse_json(result, validator)
```

## Tool middleware

Register middleware modules to inspect or transform tool calls:

```elixir
defmodule MyApp.AuditMiddleware do
  @behaviour AgentLoop.ToolMiddleware

  @impl true
  def before_execute(tool_call, _context) do
    IO.inspect(tool_call, label: "executing")
    {:ok, tool_call}
  end

  @impl true
  def after_execute(result, _tool_call, _context) do
    result
  end
end

registry =
  AgentLoop.ToolRegistry.new()
  |> AgentLoop.ToolRegistry.register_many([...])
  |> AgentLoop.ToolRegistry.add_middleware(MyApp.AuditMiddleware)
```

## MCP support

The loop can discover and call tools from MCP (Model Context Protocol) servers via stdio.

```elixir
alias AgentLoop.MCP.Server

mcp_server = %Server{
  name: "filesystem",
  command: "npx",
  args: ["-y", "@modelcontextprotocol/server-filesystem", "."]
}

config = AgentLoop.LoopConfig.new(provider, registry,
  model: "gpt-4o-mini",
  mcp_servers: [mcp_server]
)

result = AgentLoop.run(AgentLoop.RunRequest.new("List files"), config)
```

MCP tools are prefixed with `mcp_<server_name>__` so they do not collide with native tools.

## Examples

See the `examples/` directory for runnable scripts:

- `examples/basic_loop.exs` — minimal tool loop
- `examples/custom_tool.exs` — writing and registering a custom tool
- `examples/coding_agent.exs` — read/search/edit local files
- `examples/persistence.exs` — resume sessions and inspect traces
- `examples/mcp.exs` — use an MCP stdio server
- `examples/kimi_code_clone/` — a full supervised CLI agent with approval prompts

Run any example with:

```bash
export OPENAI_API_KEY=sk-...
mix run examples/basic_loop.exs
```

## Running tests

```bash
mix deps.get
mix test
mix format --check-formatted
```

## Design principles

- **Functional core**: the loop is a pure function over immutable state.
- **No process required**: add your own GenServer or LiveView later.
- **Provider-agnostic**: any LLM provider works if it implements the behaviour.
- **Easy to copy**: the whole directory can be dropped into another Mix project.

## What's intentionally left out

- Multi-tenancy / RBAC
- Messaging channels (Telegram, Slack, etc.)
- MCP bridge
- Advanced policy engine

Layer these on top when you need them.
