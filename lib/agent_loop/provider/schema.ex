defmodule AgentLoop.Provider.Schema do
  @moduledoc """
  Common internal schema for provider requests and responses.

  Providers receive a `Request` struct and must return a `Response` struct.
  Each provider is responsible for translating these normalized structs to and
  from its own API format.
  """

  alias AgentLoop.Message
  alias AgentLoop.ToolCall
  alias AgentLoop.ToolDefinition

  defmodule Request do
    @moduledoc """
    Normalized provider request.
    """

    @type t :: %__MODULE__{
            model: String.t(),
            messages: [Message.t()],
            tools: [ToolDefinition.t()] | nil,
            temperature: float() | nil,
            max_tokens: pos_integer() | nil,
            extra: map()
          }

    defstruct model: nil,
              messages: [],
              tools: nil,
              temperature: nil,
              max_tokens: nil,
              extra: %{}
  end

  defmodule Response do
    @moduledoc """
    Normalized provider response.
    """

    @type t :: %__MODULE__{
            content: String.t() | nil,
            thinking: String.t() | nil,
            tool_calls: [ToolCall.t()] | nil,
            finish_reason: String.t() | nil,
            usage: map() | nil,
            extra: map()
          }

    defstruct content: nil,
              thinking: nil,
              tool_calls: nil,
              finish_reason: nil,
              usage: nil,
              extra: %{}
  end
end
