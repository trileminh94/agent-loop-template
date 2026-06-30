defmodule AgentLoop.Tools.WriteFile do
  @moduledoc """
  Write content to a file inside the workspace, creating parent directories.
  """

  @behaviour AgentLoop.Tool

  alias AgentLoop.Tools.Workspace

  @impl true
  def name, do: "write_file"

  @impl true
  def description do
    "Write content to a file. Parent directories are created automatically. " <>
      "For large files, use append=true to build the file in chunks."
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
        "content" => %{
          "type" => "string",
          "description" => "Content to write"
        },
        "append" => %{
          "type" => "boolean",
          "description" => "Append to the file instead of overwriting"
        }
      },
      "required" => ["path", "content"]
    }
  end

  @impl true
  def execute(args, _context) do
    path = Map.get(args, "path")
    content = Map.get(args, "content", "")
    append? = Map.get(args, "append", false)

    if is_nil(path) or path == "" do
      {:error, "missing required argument: path"}
    else
      case Workspace.resolve(path) do
        {:ok, resolved} ->
          with :ok <- File.mkdir_p(Path.dirname(resolved)),
               :ok <- write(resolved, content, append?) do
            {:ok, "wrote #{Workspace.display_path(resolved)} (#{byte_size(content)} bytes)"}
          else
            {:error, reason} ->
              {:error, "could not write #{path}: #{:file.format_error(reason)}"}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp write(path, content, true) do
    case File.open(path, [:append, :utf8], fn file ->
           IO.write(file, content)
         end) do
      {:ok, :ok} -> :ok
      other -> other
    end
  end

  defp write(path, content, false) do
    File.write(path, content)
  end
end
