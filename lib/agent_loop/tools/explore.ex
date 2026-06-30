defmodule AgentLoop.Tools.Explore do
  @moduledoc """
  Quick workspace exploration.

  Returns a directory listing plus a flat list of files up to two levels deep,
  similar to:

      ls -la <path> && find <path> -maxdepth 2 -type f | head -30

  This gives the model a concise overview of a project or module.
  """

  @behaviour AgentLoop.Tool

  alias AgentLoop.Tools.Workspace

  @max_files 30

  @impl true
  def name, do: "explore"

  @impl true
  def description do
    "Explore a directory with a detailed listing plus a flat file list up to 2 levels deep. " <>
      "Use this to get a quick overview of a project or module."
  end

  @impl true
  def parameters do
    %{
      "type" => "object",
      "properties" => %{
        "path" => %{
          "type" => "string",
          "description" =>
            "Directory path (relative to workspace, or absolute). Defaults to workspace root."
        }
      },
      "required" => []
    }
  end

  @impl true
  def execute(args, _context) do
    path = Map.get(args, "path", ".")

    case Workspace.resolve(path) do
      {:ok, resolved} ->
        listing = ls_la(resolved)
        files = find_files(resolved, 2)
        output = [listing, "--- files (max depth 2, first #{@max_files}) ---", files]
        {:ok, Enum.join(output, "\n")}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ls_la(path) do
    case File.ls(path) do
      {:ok, entries} ->
        lines =
          entries
          |> Enum.sort()
          |> Enum.map(fn entry ->
            full = Path.join(path, entry)
            type = if File.dir?(full), do: "d", else: "-"
            size = file_size(full)
            "#{type} #{String.pad_leading("#{size}", 10)}  #{entry}"
          end)

        Enum.join(lines, "\n")

      {:error, reason} ->
        "could not list #{path}: #{:file.format_error(reason)}"
    end
  end

  defp find_files(path, max_depth) do
    find_files(path, max_depth, 0, path)
    |> Enum.take(@max_files)
    |> Enum.join("\n")
  end

  defp find_files(path, max_depth, depth, root) do
    if depth > max_depth do
      []
    else
      case File.ls(path) do
        {:ok, entries} ->
          Enum.flat_map(entries, fn entry ->
            full = Path.join(path, entry)
            rel = Path.relative_to(full, root)

            cond do
              File.dir?(full) -> find_files(full, max_depth, depth + 1, root)
              File.regular?(full) -> [rel]
              true -> []
            end
          end)

        {:error, _} ->
          []
      end
    end
  end

  defp file_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} -> size
      _ -> 0
    end
  end
end
