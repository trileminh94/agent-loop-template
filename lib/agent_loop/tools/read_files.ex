defmodule AgentLoop.Tools.ReadFiles do
  @moduledoc """
  Read multiple files in parallel.

  This is faster than issuing many individual `read_file` calls because the
  model can request all needed files in a single tool call.
  """

  @behaviour AgentLoop.Tool

  alias AgentLoop.Tools.Workspace

  @max_bytes 50_000
  @max_paths 10

  @impl true
  def name, do: "read_files"

  @impl true
  def description do
    "Read up to #{@max_paths} files in parallel and return a map of path -> content. " <>
      "Large files are skipped with an error entry."
  end

  @impl true
  def parameters do
    %{
      "type" => "object",
      "properties" => %{
        "paths" => %{
          "type" => "array",
          "items" => %{"type" => "string"},
          "description" =>
            "List of file paths to read (relative to workspace, or absolute). Max #{@max_paths}."
        }
      },
      "required" => ["paths"]
    }
  end

  @impl true
  def execute(%{"paths" => paths}, _context) when is_list(paths) do
    paths = Enum.take(paths, @max_paths)

    results =
      paths
      |> Task.async_stream(&read_one/1, ordered: true, max_concurrency: length(paths))
      |> Enum.zip(paths)
      |> Enum.map(fn {{:ok, result}, path} -> {path, result} end)
      |> Map.new()

    {:ok, Jason.encode!(results)}
  end

  def execute(_args, _context) do
    {:error, "missing required argument: paths"}
  end

  defp read_one(path) do
    case Workspace.resolve(path) do
      {:ok, resolved} ->
        case File.stat(resolved) do
          {:ok, %{size: size}} when size > @max_bytes ->
            "#{path} is #{size} bytes (max #{@max_bytes}); use read_file with offset/limit"

          {:ok, _} ->
            case File.read(resolved) do
              {:ok, content} -> content
              {:error, reason} -> "Error: could not read #{path}: #{:file.format_error(reason)}"
            end

          {:error, reason} ->
            "Error: could not stat #{path}: #{:file.format_error(reason)}"
        end

      {:error, reason} ->
        "Error: #{reason}"
    end
  end
end
