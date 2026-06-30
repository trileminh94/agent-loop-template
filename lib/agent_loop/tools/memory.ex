defmodule AgentLoop.Tools.Memory do
  @moduledoc """
  Persistent memory for the agent.

  `remember` stores a note in the configured persistence adapter.
  `recall` retrieves all stored notes. When no persistence is configured,
  notes are held only in memory for the current process.
  """

  @behaviour AgentLoop.Tool

  @impl true
  def name, do: "memory"

  @impl true
  def description do
    "Store or retrieve notes across agent runs. Use this to remember facts, decisions, or TODOs."
  end

  @impl true
  def parameters do
    %{
      "type" => "object",
      "properties" => %{
        "action" => %{
          "type" => "string",
          "enum" => ["remember", "recall"],
          "description" => "remember to store a note, recall to read all notes"
        },
        "note" => %{
          "type" => "string",
          "description" => "Note to store (required for remember)"
        }
      },
      "required" => ["action"]
    }
  end

  @impl true
  def execute(args, context) do
    action = Map.get(args, "action")

    case action do
      "remember" -> remember(Map.get(args, "note"), context)
      "recall" -> recall(context)
      _ -> {:error, "invalid action: #{action}"}
    end
  end

  defp remember(nil, _context) do
    {:error, "missing required argument: note"}
  end

  defp remember(note, %{persistence: persistence, session_id: session_id}) do
    if persistence do
      {adapter, state} = persistence
      adapter.remember(state, session_id, note)
      {:ok, "remembered note (#{String.length(note)} chars)"}
    else
      {:ok, "remembered note (no persistence configured)"}
    end
  end

  defp recall(%{persistence: persistence, session_id: session_id}) do
    if persistence do
      {adapter, state} = persistence

      case adapter.recall(state, session_id, []) do
        {:ok, ""} -> {:ok, "(no memories yet)"}
        {:ok, content} -> {:ok, content}
        {:error, reason} -> {:error, "could not recall memory: #{inspect(reason)}"}
      end
    else
      {:ok, "(no persistence configured)"}
    end
  end
end
