defmodule AgentLoop.RunResult do
  @moduledoc """
  Output of a single agent-loop run.
  """

  alias AgentLoop.Message

  @type t :: %__MODULE__{
          content: String.t() | nil,
          thinking: String.t() | nil,
          messages: [Message.t()],
          iterations: non_neg_integer(),
          total_tool_calls: non_neg_integer(),
          usage: map() | nil,
          finish_reason: :complete | :max_iterations | :error | atom()
        }

  defstruct content: nil,
            thinking: nil,
            messages: [],
            iterations: 0,
            total_tool_calls: 0,
            usage: nil,
            finish_reason: :complete
end
