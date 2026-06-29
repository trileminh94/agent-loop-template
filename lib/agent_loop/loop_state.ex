defmodule AgentLoop.LoopState do
  @moduledoc """
  Internal mutable state used during a single run of the agent loop.
  """

  alias AgentLoop.Message

  @type t :: %__MODULE__{
          messages: [Message.t()],
          iteration: non_neg_integer(),
          total_tool_calls: non_neg_integer(),
          pending_messages: [Message.t()],
          final_content: String.t() | nil,
          final_thinking: String.t() | nil,
          usage: map() | nil,
          truncation_retries: non_neg_integer(),
          finish_reason: :complete | :max_iterations | :error | atom()
        }

  defstruct messages: [],
            iteration: 0,
            total_tool_calls: 0,
            pending_messages: [],
            final_content: nil,
            final_thinking: nil,
            usage: nil,
            truncation_retries: 0,
            finish_reason: :complete
end
