defmodule AgentLoop.Support.ContextLengthProvider do
  @moduledoc """
  Test provider that simulates a context-length error once, then succeeds.
  """

  @behaviour AgentLoop.Provider

  alias AgentLoop.Provider.Schema

  defstruct response: %{content: "ok"}

  @impl true
  def chat(%__MODULE__{response: response}, request) do
    already_failed = Process.get({__MODULE__, :failed}, false)

    if not already_failed and length(request.messages) > 2 do
      Process.put({__MODULE__, :failed}, true)

      {:error,
       %{
         status: 400,
         body: %{
           "error" => %{
             "code" => "context_length_exceeded",
             "message" => "This model's maximum context length is exceeded."
           }
         }
       }}
    else
      response =
        case response do
          %Schema.Response{} = response -> response
          map -> struct(Schema.Response, map)
        end

      {:ok, response}
    end
  end
end
