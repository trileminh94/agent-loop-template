defmodule AgentLoop.Persistence do
  @moduledoc """
  Behaviour for persistence adapters.

  Implementations store sessions (messages + metadata), memory notes, and
  execution traces. The loop uses this behaviour to resume conversations,
  recall facts, and inspect runs later.

  The loop always holds a `{adapter, state}` tuple; the state is opaque to
  callers. See `AgentLoop.Persistence.NoOp` for a zero-side-effect default and
  `AgentLoop.Persistence.SQLite` for a concrete file-backed implementation.
  """

  alias AgentLoop.Message

  @type t :: {module(), state :: any()}
  @type session_id :: String.t() | nil
  @type run_id :: String.t() | nil

  @callback init(opts :: keyword()) :: {:ok, state :: any()} | {:error, any()}

  @callback save_session(
              state :: any(),
              session_id :: session_id(),
              messages :: [Message.t()],
              metadata :: map()
            ) :: :ok | {:error, any()}

  @callback load_session(state :: any(), session_id :: String.t()) ::
              {:ok, %{messages: [Message.t()], metadata: map()}} | {:error, any()}

  @callback list_sessions(state :: any(), opts :: keyword()) ::
              {:ok, [map()]} | {:error, any()}

  @callback remember(state :: any(), session_id :: session_id(), note :: String.t()) ::
              :ok | {:error, any()}

  @callback recall(state :: any(), session_id :: session_id(), opts :: keyword()) ::
              {:ok, String.t()} | {:error, any()}

  @callback write_trace(
              state :: any(),
              session_id :: session_id(),
              run_id :: run_id(),
              event :: map()
            ) :: :ok | {:error, any()}

  @callback get_trace(state :: any(), session_id :: session_id(), run_id :: run_id()) ::
              {:ok, [map()]} | {:error, any()}

  @doc "Initialize an adapter with options and return a persistence tuple."
  def new(adapter, opts \\ []) do
    case adapter.init(opts) do
      {:ok, state} -> {:ok, {adapter, state}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Delegate a call to the adapter in the persistence tuple."
  def call({adapter, state}, function, args) when is_atom(function) and is_list(args) do
    apply(adapter, function, [state | args])
  end
end
