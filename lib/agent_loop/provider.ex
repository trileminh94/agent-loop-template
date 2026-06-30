defmodule AgentLoop.Provider do
  @moduledoc """
  Behaviour for LLM providers.

  Implementations translate the agent loop's normalized `Schema.Request` into
  provider-specific HTTP calls and return a normalized `Schema.Response`.
  """

  alias AgentLoop.Provider.Schema

  @type chat_request :: Schema.Request.t()

  @type chat_response :: Schema.Response.t()

  @callback chat(provider :: any(), request :: chat_request()) ::
              {:ok, chat_response()} | {:error, any()}

  @callback chat_stream(provider :: any(), request :: chat_request(), callback :: function()) ::
              {:ok, chat_response()} | {:error, any()}

  @optional_callbacks chat_stream: 3
end
