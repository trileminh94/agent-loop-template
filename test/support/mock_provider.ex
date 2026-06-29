defmodule AgentLoop.Support.MockProvider do
  @moduledoc """
  Test provider that returns pre-programmed responses.

  Uses the process dictionary to track the current response index so that
  successive calls in the same loop return different responses.
  """

  @behaviour AgentLoop.Provider

  defstruct responses: []

  @impl true
  def chat(%__MODULE__{responses: responses}, _request) do
    index = Process.get({__MODULE__, :index}, 0)
    response = Enum.at(responses, index, %{content: "done"})
    Process.put({__MODULE__, :index}, index + 1)
    {:ok, response}
  end
end
