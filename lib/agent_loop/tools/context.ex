defmodule AgentLoop.Tools.Context do
  @moduledoc """
  Per-tool-execution context.

  The loop builds a context value and passes it to every tool execution.
  Tools receive the context as the second argument to `execute/2`, keeping
  tool modules stateless and safe for concurrent execution.
  """

  alias AgentLoop.Persistence

  @type t :: %__MODULE__{
          session_id: String.t() | nil,
          persistence: Persistence.t() | nil,
          mcp_clients: %{String.t() => AgentLoop.MCP.Client.t()},
          approved: boolean()
        }

  defstruct session_id: nil,
            persistence: nil,
            mcp_clients: %{},
            approved: false
end
