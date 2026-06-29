defmodule AgentLoop.RunRequest do
  @moduledoc """
  Input to a single agent-loop run.

  ## Sessions

  Provide a `session_id` to resume a previous conversation. The loop will load
  persisted history before the run and save the updated history after. A `run_id`
  is generated automatically for tracing; pass one explicitly to correlate traces.
  """

  alias AgentLoop.Message

  @type t :: %__MODULE__{
          message: String.t(),
          history: [Message.t()],
          system_prompt: String.t() | nil,
          session_id: String.t() | nil,
          run_id: String.t() | nil,
          metadata: map()
        }

  defstruct message: "",
            history: [],
            system_prompt: nil,
            session_id: nil,
            run_id: nil,
            metadata: %{}

  @doc "Build a request from a user message."
  def new(message, opts \\ []) when is_binary(message) do
    %__MODULE__{
      message: message,
      history: Keyword.get(opts, :history, []),
      system_prompt: Keyword.get(opts, :system_prompt),
      session_id: Keyword.get(opts, :session_id),
      run_id: Keyword.get(opts, :run_id, generate_run_id()),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  defp generate_run_id do
    Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
end
