defmodule AgentLoop.Provider.DeepSeek do
  @moduledoc """
  DeepSeek provider.

  DeepSeek's API is OpenAI-compatible, so this is a thin wrapper around
  `AgentLoop.Provider.OpenAICompatible` with the DeepSeek base URL and a
  custom auth header.

  ## Usage

      provider = %AgentLoop.Provider.DeepSeek{
        api_key: System.get_env("DEEPSEEK_API_KEY")
      }

  """

  @behaviour AgentLoop.Provider

  alias AgentLoop.Provider.OpenAICompatible

  defstruct api_key: nil,
            base_url: "https://api.deepseek.com",
            http_options: [receive_timeout: 120_000]

  @type t :: %__MODULE__{
          api_key: String.t() | nil,
          base_url: String.t(),
          http_options: keyword()
        }

  @impl true
  def chat(%__MODULE__{} = provider, request) do
    OpenAICompatible.chat(
      %OpenAICompatible{
        api_key: provider.api_key,
        base_url: provider.base_url,
        http_options: provider.http_options
      },
      request
    )
  end
end
