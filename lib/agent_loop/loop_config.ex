defmodule AgentLoop.LoopConfig do
  @moduledoc """
  Configuration for the agent loop.

  ## Persistence

  Pass a `persistence` tuple (usually obtained via `AgentLoop.Persistence.new/2`)
  to enable session history, memory, and traces. Set `trace: true` to persist
  every loop event.

      {:ok, persistence} = AgentLoop.Persistence.new(AgentLoop.Persistence.SQLite, database: "data.db")

      config = AgentLoop.LoopConfig.new(provider, registry,
        persistence: persistence,
        trace: true
      )
  """

  alias AgentLoop.MCP.Server, as: MCPServer
  alias AgentLoop.Persistence
  alias AgentLoop.Persistence.NoOp
  alias AgentLoop.ToolRegistry

  @type event_callback :: (AgentLoop.Event.t() -> any())

  @type t :: %__MODULE__{
          provider: any(),
          model: String.t(),
          registry: ToolRegistry.t(),
          system_prompt: String.t() | nil,
          max_iterations: pos_integer(),
          max_tool_calls: non_neg_integer(),
          max_tokens: pos_integer() | nil,
          temperature: float(),
          event_callback: event_callback() | nil,
          tool_call_prefix: String.t() | nil,
          allow_tools: [String.t()] | nil,
          deny_tools: [String.t()] | nil,
          persistence: Persistence.t(),
          trace: boolean(),
          session_id: String.t() | nil,
          mcp_servers: [MCPServer.t()],
          mcp_clients: %{String.t() => any()},
          stream: boolean(),
          max_retries: non_neg_integer(),
          retry_backoff_ms: non_neg_integer(),
          retry_on: (any() -> boolean()) | nil,
          truncation_strategy: :drop_oldest | nil,
          max_truncation_retries: non_neg_integer(),
          tool_timeout_ms: pos_integer() | :infinity,
          approval: module() | nil
        }

  defstruct provider: nil,
            model: "gpt-4o-mini",
            registry: nil,
            system_prompt: nil,
            max_iterations: 10,
            max_tool_calls: 50,
            max_tokens: nil,
            temperature: 0.7,
            event_callback: nil,
            tool_call_prefix: nil,
            allow_tools: nil,
            deny_tools: nil,
            persistence: {NoOp, nil},
            trace: false,
            session_id: nil,
            mcp_servers: [],
            mcp_clients: %{},
            stream: false,
            max_retries: 0,
            retry_backoff_ms: 1000,
            retry_on: nil,
            truncation_strategy: nil,
            max_truncation_retries: 1,
            tool_timeout_ms: 60_000,
            approval: nil

  @doc "Create a config with required fields."
  def new(provider, registry, opts \\ []) do
    persistence = Keyword.get(opts, :persistence, {NoOp, nil})
    trace = Keyword.get(opts, :trace, false)

    %__MODULE__{
      provider: provider,
      registry: registry,
      model: Keyword.get(opts, :model, "gpt-4o-mini"),
      system_prompt: Keyword.get(opts, :system_prompt),
      max_iterations: Keyword.get(opts, :max_iterations, 10),
      max_tool_calls: Keyword.get(opts, :max_tool_calls, 50),
      max_tokens: Keyword.get(opts, :max_tokens),
      temperature: Keyword.get(opts, :temperature, 0.7),
      event_callback: Keyword.get(opts, :event_callback),
      tool_call_prefix: Keyword.get(opts, :tool_call_prefix),
      allow_tools: Keyword.get(opts, :allow_tools),
      deny_tools: Keyword.get(opts, :deny_tools),
      persistence: persistence,
      trace: trace,
      mcp_servers: Keyword.get(opts, :mcp_servers, []),
      mcp_clients: Keyword.get(opts, :mcp_clients, %{}),
      stream: Keyword.get(opts, :stream, false),
      max_retries: Keyword.get(opts, :max_retries, 0),
      retry_backoff_ms: Keyword.get(opts, :retry_backoff_ms, 1000),
      retry_on: Keyword.get(opts, :retry_on, nil),
      truncation_strategy: Keyword.get(opts, :truncation_strategy, nil),
      max_truncation_retries: Keyword.get(opts, :max_truncation_retries, 1),
      tool_timeout_ms: Keyword.get(opts, :tool_timeout_ms, 60_000),
      approval: Keyword.get(opts, :approval, nil)
    }
  end
end
