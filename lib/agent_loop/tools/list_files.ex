defmodule AgentLoop.Tools.ListFiles do
  @moduledoc """
  List files and directories inside the workspace.
  """

  @behaviour AgentLoop.Tool

  alias AgentLoop.Tools.Workspace

  @impl true
  def name, do: "list_files"

  @impl true
  def description do
    "List files and directories in a workspace path. Omit path to list the workspace root."
  end

  @impl true
  def parameters do
    %{
      "type" => "object",
      "properties" => %{
        "path" => %{
          "type" => "string",
          "description" => "Directory path (relative to workspace, or absolute)"
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
        case File.ls(resolved) do
          {:ok, entries} ->
            lines =
              entries
              |> Enum.sort()
              |> Enum.map(fn entry ->
                full = Path.join(resolved, entry)

                case File.dir?(full) do
                  true -> "[DIR]  #{entry}/"
                  false -> "[FILE] #{entry}"
                end
              end)

            {:ok, Enum.join(lines, "\n")}

          {:error, reason} ->
            {:error, "could not list #{path}: #{:file.format_error(reason)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
