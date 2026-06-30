defmodule AgentLoop.ToolResult do
  @moduledoc """
  The result of executing a tool.

  `content` is sent back to the LLM. `user_content` is an optional separate
  message shown to the user (e.g. a pretty summary). `silent` suppresses the
  user-visible message entirely.
  """

  @type t :: %__MODULE__{
          tool_call_id: String.t(),
          name: String.t(),
          content: String.t(),
          user_content: String.t() | nil,
          is_error: boolean(),
          silent: boolean()
        }

  defstruct tool_call_id: nil,
            name: nil,
            content: "",
            user_content: nil,
            is_error: false,
            silent: false

  @doc "Create a successful tool result."
  def ok(tool_call_id, name, content) do
    %__MODULE__{
      tool_call_id: tool_call_id,
      name: name,
      content: sanitize(content),
      is_error: false
    }
  end

  @doc "Create a successful tool result with separate user-facing content."
  def ok(tool_call_id, name, content, user_content) do
    %__MODULE__{
      tool_call_id: tool_call_id,
      name: name,
      content: sanitize(content),
      user_content: sanitize(user_content),
      is_error: false
    }
  end

  @doc "Create an error tool result."
  def error(tool_call_id, name, reason) do
    %__MODULE__{
      tool_call_id: tool_call_id,
      name: name,
      content: sanitize("Error: #{reason}"),
      is_error: true
    }
  end

  defp sanitize(value) do
    value |> to_string() |> String.replace_invalid("�")
  end

  @doc "Return the content intended for the LLM."
  def for_llm(%__MODULE__{} = result), do: result.content

  @doc "Return the content intended for the user, if any."
  def for_user(%__MODULE__{} = result), do: result.user_content
end
