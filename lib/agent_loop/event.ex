defmodule AgentLoop.Event do
  @moduledoc """
  Event emitted during a run for streaming UI updates and observability.
  """

  @type t :: %__MODULE__{
          type: atom(),
          payload: map(),
          timestamp: DateTime.t()
        }

  defstruct type: nil,
            payload: %{},
            timestamp: nil

  @doc "Create an event."
  def new(type, payload \\ %{}) do
    %__MODULE__{
      type: type,
      payload: payload,
      timestamp: DateTime.utc_now()
    }
  end
end
