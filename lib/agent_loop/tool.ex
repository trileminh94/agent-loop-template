defmodule AgentLoop.Tool do
  @moduledoc """
  Behaviour for tools that the agent loop can invoke.

  Tools receive their parsed arguments and an execution context. The context
  carries session id, persistence adapter, MCP clients, and any other
  per-run state the tool needs. This keeps tool modules stateless and
  thread-safe for concurrent execution.
  """

  @doc "Return the tool name as exposed to the LLM."
  @callback name() :: String.t()

  @doc "Return a short description for the LLM."
  @callback description() :: String.t()

  @doc "Return a JSON-schema description of the tool parameters."
  @callback parameters() :: map()

  @doc """
  Execute the tool.

  Returns `{:ok, content}` or `{:error, reason}`. The content is sent back to
  the LLM as the tool result.

  For more control over what is shown to the user vs. the LLM, return
  `{:ok, llm_content, user_content}`.
  """
  @callback execute(args :: map(), context :: AgentLoop.Tools.Context.t()) ::
              {:ok, String.t()}
              | {:ok, String.t(), String.t()}
              | {:error, String.t()}
end
