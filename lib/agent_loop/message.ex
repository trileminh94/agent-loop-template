defmodule AgentLoop.Message do
  @moduledoc """
  Represents a single message in the agent conversation.

  Roles follow the OpenAI-compatible convention:
  - `:system` — instructions and context
  - `:user` — user input
  - `:assistant` — model output, optionally including tool calls
  - `:tool` — tool result response
  """

  alias AgentLoop.ToolCall

  @type t :: %__MODULE__{
          role: :system | :user | :assistant | :tool,
          content: String.t() | nil,
          tool_calls: [ToolCall.t()] | nil,
          tool_call_id: String.t() | nil,
          name: String.t() | nil
        }

  defstruct role: :user,
            content: nil,
            tool_calls: nil,
            tool_call_id: nil,
            name: nil

  @doc "Create a system message."
  def system(content) when is_binary(content) do
    %__MODULE__{role: :system, content: content}
  end

  @doc "Create a user message."
  def user(content) when is_binary(content) do
    %__MODULE__{role: :user, content: content}
  end

  @doc "Create an assistant message (optionally with tool calls)."
  def assistant(content, opts \\ []) when is_binary(content) or is_nil(content) do
    %__MODULE__{
      role: :assistant,
      content: content,
      tool_calls: Keyword.get(opts, :tool_calls)
    }
  end

  @doc "Create a tool result message."
  def tool(tool_call_id, content, opts \\ []) when is_binary(tool_call_id) do
    %__MODULE__{
      role: :tool,
      tool_call_id: tool_call_id,
      content: content,
      name: Keyword.get(opts, :name)
    }
  end
end
