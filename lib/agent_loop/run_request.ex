defmodule AgentLoop.RunRequest do
  @moduledoc """
  Input to a single agent-loop run.
  """

  alias AgentLoop.Message

  @type t :: %__MODULE__{
          message: String.t(),
          history: [Message.t()],
          system_prompt: String.t() | nil,
          metadata: map()
        }

  defstruct message: "",
            history: [],
            system_prompt: nil,
            metadata: %{}

  @doc "Build a request from a user message."
  def new(message, opts \\ []) when is_binary(message) do
    %__MODULE__{
      message: message,
      history: Keyword.get(opts, :history, []),
      system_prompt: Keyword.get(opts, :system_prompt),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end
end
