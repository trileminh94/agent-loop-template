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
    new(tool_module)
  end

  @doc """
  Build a definition with optional overrides.

  ## Options

    * `:name` - override the function name
    * `:description` - override the description
    * `:parameters` - override the parameters
  """
  def new(tool_module, opts \\ []) do
    %__MODULE__{
      type: "function",
      function: %{
        name: Keyword.get(opts, :name, tool_module.name()),
        description: Keyword.get(opts, :description, tool_module.description()),
        parameters: Keyword.get(opts, :parameters, tool_module.parameters())
      }
    }
  end
end
