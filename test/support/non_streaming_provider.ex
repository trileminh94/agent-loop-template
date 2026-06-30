defmodule AgentLoop.Support.NonStreamingProvider do
  @moduledoc """
  Test provider that only implements chat/2, not chat_stream/3.
  """

  @behaviour AgentLoop.Provider

  alias AgentLoop.Provider.Schema

  defstruct responses: []

  @impl true
  def chat(%__MODULE__{responses: responses}, _request) do
    index = Process.get({__MODULE__, :index}, 0)

    response =
      case Enum.at(responses, index, %{content: "done"}) do
        %Schema.Response{} = response -> response
        map -> struct(Schema.Response, map)
      end

    Process.put({__MODULE__, :index}, index + 1)
    {:ok, response}
  end
end
