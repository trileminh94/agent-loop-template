defmodule AgentLoop.Tools.EditFile do
  @moduledoc """
  Edit a file by replacing an exact string with another string.

  This is the safest way to modify existing files without rewriting the
  entire content. Use replace_all=true to change every occurrence.
  """

  @behaviour AgentLoop.Tool

  alias AgentLoop.Tools.Workspace

  @impl true
  def name, do: "edit_file"

  @impl true
  def description do
    "Edit a file by replacing an exact old_string with new_string. " <>
      "Fails unless the old_string matches exactly once (unless replace_all is true)."
  end

  @impl true
  def parameters do
    %{
      "type" => "object",
      "properties" => %{
        "path" => %{
          "type" => "string",
          "description" => "File path (relative to workspace, or absolute)"
        },
        "old_string" => %{
          "type" => "string",
          "description" => "Exact text to find"
        },
        "new_string" => %{
          "type" => "string",
          "description" => "Replacement text"
        },
        "replace_all" => %{
          "type" => "boolean",
          "description" => "Replace every occurrence instead of requiring a unique match"
        }
      },
      "required" => ["path", "old_string", "new_string"]
    }
  end

  @impl true
  def execute(args) do
    path = Map.get(args, "path")
    old_string = Map.get(args, "old_string")
    new_string = Map.get(args, "new_string")
    replace_all? = Map.get(args, "replace_all", false)

    cond do
      is_nil(path) or path == "" ->
        {:error, "missing required argument: path"}

      is_nil(old_string) or old_string == "" ->
        {:error, "missing required argument: old_string"}

      true ->
        case Workspace.resolve(path) do
          {:ok, resolved} ->
            case File.read(resolved) do
              {:ok, content} ->
                apply_edit(resolved, content, old_string, new_string, replace_all?)

              {:error, reason} ->
                {:error, "could not read #{path}: #{:file.format_error(reason)}"}
            end

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp apply_edit(path, content, old, new, replace_all?) do
    occurrences = content |> :binary.matches(old) |> length()

    cond do
      occurrences == 0 ->
        {:error, "old_string not found in #{path}"}

      occurrences > 1 and not replace_all? ->
        {:error, "old_string appears #{occurrences} times in #{path}; use replace_all=true"}

      true ->
        new_content = String.replace(content, old, new, global: replace_all?)

        case File.write(path, new_content) do
          :ok ->
            {:ok, "edited #{Workspace.display_path(path)} (#{occurrences} replacement(s))"}

          {:error, reason} ->
            {:error, "could not write #{path}: #{:file.format_error(reason)}"}
        end
    end
  end
end
