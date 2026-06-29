defmodule AgentLoop.ToolCall do
  @moduledoc """
  A tool invocation requested by the LLM.
  """

  @derive {Jason.Encoder, only: [:id, :name, :arguments, :parse_error]}

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          arguments: %{String.t() => any()},
          parse_error: String.t() | nil
        }

  defstruct id: nil,
            name: nil,
            arguments: %{},
            parse_error: nil
end
