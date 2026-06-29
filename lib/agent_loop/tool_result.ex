defmodule AgentLoop.ToolResult do
  @moduledoc """
  The result of executing a tool.
  """

  @type t :: %__MODULE__{
          tool_call_id: String.t(),
          name: String.t(),
          content: String.t(),
          is_error: boolean()
        }

  defstruct tool_call_id: nil,
            name: nil,
            content: "",
            is_error: false

  @doc "Create a successful tool result."
  def ok(tool_call_id, name, content) do
    %__MODULE__{
      tool_call_id: tool_call_id,
      name: name,
      content: to_string(content),
      is_error: false
    }
  end

  @doc "Create an error tool result."
  def error(tool_call_id, name, reason) do
    %__MODULE__{
      tool_call_id: tool_call_id,
      name: name,
      content: "Error: #{reason}",
      is_error: true
    }
  end
end
