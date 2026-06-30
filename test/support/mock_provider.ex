defmodule AgentLoop.Support.MockProvider do
  @moduledoc """
  Test provider that returns pre-programmed responses.

  Uses the process dictionary to track the current response index so that
  successive calls in the same loop return different responses.
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

  @impl true
  def chat_stream(%__MODULE__{responses: responses}, _request, callback) do
    index = Process.get({__MODULE__, :index}, 0)

    response =
      case Enum.at(responses, index, %{content: "done"}) do
        %Schema.Response{} = response -> response
        map -> struct(Schema.Response, map)
      end

    if is_binary(response.content) do
      callback.({:content_delta, response.content})
    end

    Process.put({__MODULE__, :index}, index + 1)
    {:ok, response}
  end
end
