defmodule AgentLoop.ToolMiddleware do
  @moduledoc """
  Behaviour for tool execution middleware.

  Middleware modules can inspect or transform a tool call before it runs and
  inspect or transform the result after it runs. They are executed in the order
  they were added to the registry.
  """

  alias AgentLoop.ToolCall
  alias AgentLoop.ToolResult

  @doc """
  Called before a tool is executed.

  Return `{:ok, tool_call}` to continue with the (possibly modified) call, or
  `{:error, reason}` to short-circuit with an error result.
  """
  @callback before_execute(tool_call :: ToolCall.t(), context :: any()) ::
              {:ok, ToolCall.t()} | {:error, any()}

  @doc """
  Called after a tool is executed.

  Return the (possibly modified) result.
  """
  @callback after_execute(result :: ToolResult.t(), tool_call :: ToolCall.t(), context :: any()) ::
              ToolResult.t()
end
