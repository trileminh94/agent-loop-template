defmodule AgentLoop.Support.FlakyProvider do
  @moduledoc """
  Test provider that fails a configurable number of times before succeeding.
  """

  @behaviour AgentLoop.Provider

  alias AgentLoop.Provider.Schema

  defstruct failures: 0, response: %{content: "done"}

  @impl true
  def chat(%__MODULE__{failures: failures, response: response}, _request) do
    failures_remaining = Process.get({__MODULE__, :failures_remaining}, failures)

    if failures_remaining > 0 do
      Process.put({__MODULE__, :failures_remaining}, failures_remaining - 1)
      {:error, :transient}
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
