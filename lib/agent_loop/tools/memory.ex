defmodule AgentLoop.Tools.Memory do
  @moduledoc """
  Simple file-based memory for the agent.

  `remember` appends a note to `.agent_loop/memory.md` in the workspace.
  `recall` reads all stored notes. This is a minimal stand-in for goclaw's
  memory/knowledge-graph layer.
  """

  @behaviour AgentLoop.Tool

  alias AgentLoop.Tools.Workspace

  @memory_file ".agent_loop/memory.md"

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
  def execute(args) do
    action = Map.get(args, "action")

    case action do
      "remember" -> remember(Map.get(args, "note"))
      "recall" -> recall()
      _ -> {:error, "invalid action: #{action}"}
    end
  end

  defp remember(nil) do
    {:error, "missing required argument: note"}
  end

  defp remember(note) do
    with {:ok, resolved} <- memory_path(),
         :ok <- File.mkdir_p(Path.dirname(resolved)),
         entry = format_entry(note),
         :ok <- File.write(resolved, entry, [:append]) do
      {:ok, "remembered note (#{String.length(note)} chars)"}
    else
      {:error, reason} when is_atom(reason) ->
        {:error, "could not write memory: #{:file.format_error(reason)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp recall do
    with {:ok, resolved} <- memory_path() do
      case File.read(resolved) do
        {:ok, content} -> {:ok, content}
        {:error, :enoent} -> {:ok, "(no memories yet)"}
        {:error, reason} -> {:error, "could not read memory: #{:file.format_error(reason)}"}
      end
    end
  end

  defp memory_path do
    Workspace.resolve(@memory_file)
  end

  defp format_entry(note) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    "\n## #{timestamp}\n\n#{note}\n"
  end
end
