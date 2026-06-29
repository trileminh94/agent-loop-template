defmodule AgentLoop.Provider do
  @moduledoc """
  Behaviour for LLM providers.

  Implementations translate the agent loop's request into provider-specific
  HTTP calls and return a normalized response.
  """

  alias AgentLoop.Message
  alias AgentLoop.ToolDefinition
  alias AgentLoop.ToolCall

  @type chat_request :: %{
          required(:model) => String.t(),
          required(:messages) => [Message.t()],
          optional(:tools) => [ToolDefinition.t()],
          optional(:temperature) => float(),
          optional(:max_tokens) => pos_integer(),
          optional(any()) => any()
        }

  @type chat_response :: %{
          required(:content) => String.t() | nil,
          optional(:thinking) => String.t() | nil,
          optional(:tool_calls) => [ToolCall.t()],
          optional(:finish_reason) => String.t(),
          optional(:usage) => map(),
          optional(any()) => any()
        }

  @callback chat(provider :: any(), request :: chat_request()) ::
              {:ok, chat_response()} | {:error, any()}

  @callback chat_stream(provider :: any(), request :: chat_request(), callback :: function()) ::
              {:ok, chat_response()} | {:error, any()}

  @optional_callbacks chat_stream: 3
end
