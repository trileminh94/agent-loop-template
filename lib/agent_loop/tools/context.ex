defmodule AgentLoop.Tools.Context do
  @moduledoc """
  Per-tool-execution context.

  The loop sets this before executing tools so that stateful tools (like
  `memory`) can reach the current session and persistence adapter without
  changing the public `AgentLoop.Tool` behaviour signature.

  Values are stored in the process dictionary because tools may run inside
  `Task.async_stream`; the dictionary is copied to child processes.
  """

  @key __MODULE__

  @type t :: %{
          session_id: String.t() | nil,
          persistence: AgentLoop.Persistence.t() | nil
        }

  @doc "Set the context for the current process."
  def put(session_id, persistence) do
    Process.put(@key, %{session_id: session_id, persistence: persistence})
  end

  @doc "Get the current context."
  def get do
    Process.get(@key, %{session_id: nil, persistence: nil})
  end

  @doc "Clear the context."
  def clear do
    Process.delete(@key)
  end
end
