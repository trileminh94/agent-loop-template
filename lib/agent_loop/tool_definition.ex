defmodule AgentLoop.ToolDefinition do
  @moduledoc """
  Tool schema sent to the LLM provider.

  Matches the OpenAI-style function-calling format:
  ```json
  {
    "type": "function",
    "function": {
      "name": "...",
      "description": "...",
      "parameters": { "type": "object", "properties": {}, "required": [] }
    }
  }
  ```
  """

  @type t :: %__MODULE__{
          type: String.t(),
          function: %{
            name: String.t(),
            description: String.t(),
            parameters: map()
          }
        }

  defstruct type: "function",
            function: %{name: "", description: "", parameters: %{}}

  @doc "Build a definition from a tool module implementing the AgentLoop.Tool behaviour."
  def from_module(tool_module) do
    %__MODULE__{
      type: "function",
      function: %{
        name: tool_module.name(),
        description: tool_module.description(),
        parameters: tool_module.parameters()
      }
    }
  end
end
