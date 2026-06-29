defmodule AgentLoop.LoopConfig do
  @moduledoc """
  Configuration for the agent loop.
  """

  alias AgentLoop.ToolRegistry

  @type event_callback :: (AgentLoop.Event.t() -> any())

  @type t :: %__MODULE__{
          provider: any(),
          model: String.t(),
          registry: ToolRegistry.t(),
          system_prompt: String.t() | nil,
          max_iterations: pos_integer(),
          max_tool_calls: non_neg_integer(),
          max_tokens: pos_integer() | nil,
          temperature: float(),
          event_callback: event_callback() | nil,
          tool_call_prefix: String.t() | nil,
          allow_tools: [String.t()] | nil,
          deny_tools: [String.t()] | nil
        }

  defstruct provider: nil,
            model: "gpt-4o-mini",
            registry: nil,
            system_prompt: nil,
            max_iterations: 10,
            max_tool_calls: 50,
            max_tokens: nil,
            temperature: 0.7,
            event_callback: nil,
            tool_call_prefix: nil,
            allow_tools: nil,
            deny_tools: nil

  @doc "Create a config with required fields."
  def new(provider, registry, opts \\ []) do
    %__MODULE__{
      provider: provider,
      registry: registry,
      model: Keyword.get(opts, :model, "gpt-4o-mini"),
      system_prompt: Keyword.get(opts, :system_prompt),
      max_iterations: Keyword.get(opts, :max_iterations, 10),
      max_tool_calls: Keyword.get(opts, :max_tool_calls, 50),
      max_tokens: Keyword.get(opts, :max_tokens),
      temperature: Keyword.get(opts, :temperature, 0.7),
      event_callback: Keyword.get(opts, :event_callback),
      tool_call_prefix: Keyword.get(opts, :tool_call_prefix),
      allow_tools: Keyword.get(opts, :allow_tools),
      deny_tools: Keyword.get(opts, :deny_tools)
    }
  end
end
