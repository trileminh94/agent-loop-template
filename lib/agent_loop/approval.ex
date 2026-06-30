defmodule AgentLoop.Approval do
  @moduledoc """
  Behaviour for pluggable tool approval.

  Implementations decide which tool calls need explicit user approval and how
  to request it. This lets the same agent loop drive terminal prompts, web UI
  confirmations, API gates, audit-only policies, etc.

  ## Example

      defmodule MyApp.WebApproval do
        @behaviour AgentLoop.Approval

        @impl true
        def requires_approval?(%AgentLoop.ToolCall{name: "shell_exec"}, _context) do
          true
        end

        def requires_approval?(_tool_call, _context), do: false

        @impl true
        def approve(tool_call, _context) do
          # Wait for a user action, an API callback, etc.
          case MyApp.WebApproval.await_user(tool_call.id) do
            :ok -> :ok
            :deny -> {:error, "user denied \#{tool_call.name}"}
          end
        end
      end
  """

  alias AgentLoop.ToolCall
  alias AgentLoop.Tools.Context

  @doc "Return true if this tool call should block for approval before executing."
  @callback requires_approval?(tool_call :: ToolCall.t(), context :: Context.t()) :: boolean()

  @doc """
  Request approval for a tool call.

  Return `:ok` to allow execution, or `{:error, reason}` to deny it. The loop
  will surface a tool error result with the given reason.
  """
  @callback approve(tool_call :: ToolCall.t(), context :: Context.t()) ::
              :ok | {:error, String.t()}
end
