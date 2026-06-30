defmodule AgentLoop.Tools.ReadFile do
  @moduledoc """
  Read a file from disk, with optional line-range pagination.

  Paths are resolved against the configured workspace. By default, reads are
  restricted to the workspace root.
  """

  @behaviour AgentLoop.Tool

  alias AgentLoop.Tools.Workspace

  @max_bytes 50_000

  @impl true
  def name, do: "read_file"

  @impl true
  def description do
    "Read the contents of a file. For large files, use offset and limit to read a specific line range."
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
        "offset" => %{
          "type" => "integer",
          "description" => "Start reading from this 1-based line number. Defaults to 1."
        },
        "limit" => %{
          "type" => "integer",
          "description" => "Maximum number of lines to return. Omit to read the whole file."
        }
      },
      "required" => ["path"]
    }
  end

  @impl true
  def execute(args, _context) do
    path = Map.get(args, "path")
    offset = max(Map.get(args, "offset", 1) - 1, 0)
    limit = Map.get(args, "limit")

    if is_nil(path) or path == "" do
      {:error, "missing required argument: path"}
    else
      case Workspace.resolve(path) do
        {:ok, resolved} ->
          case File.stat(resolved) do
            {:ok, %{size: size}} when size > @max_bytes ->
              {:error,
               "#{path} is #{size} bytes (max #{@max_bytes}); use offset/limit or read a smaller file"}

            {:ok, _} ->
              case File.read(resolved) do
                {:ok, content} ->
                  content
                  |> slice_lines(offset, limit)
                  |> then(&{:ok, &1})

                {:error, reason} ->
                  {:error, "could not read #{path}: #{:file.format_error(reason)}"}
              end

            {:error, reason} ->
              {:error, "could not stat #{path}: #{:file.format_error(reason)}"}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp slice_lines(content, 0, nil), do: content

  defp slice_lines(content, offset, limit) do
    content
    |> String.split("\n")
    |> Enum.drop(offset)
    |> maybe_take(limit)
    |> Enum.join("\n")
  end

  defp maybe_take(lines, nil), do: lines
  defp maybe_take(lines, limit) when is_integer(limit) and limit > 0, do: Enum.take(lines, limit)
  defp maybe_take(lines, _), do: lines
end
