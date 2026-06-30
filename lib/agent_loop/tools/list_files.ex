defmodule AgentLoop.Tools.ListFiles do
  @moduledoc """
  List files and directories inside the workspace.

  Supports recursive listing and a details mode that includes file sizes and
  marks binary/build artifacts so the model can decide what to read.
  """

  @behaviour AgentLoop.Tool

  alias AgentLoop.Tools.Workspace

  @binary_extensions ~w(.beam .ez .zip .tar .gz .exe .dll .so .dylib .png .jpg .jpeg .gif .pdf)
  @skipped_dirs ~w(_build deps node_modules .git .elixir_ls)

  @impl true
  def name, do: "list_files"

  @impl true
  def description do
    "List files and directories in a workspace path. Use recursive=true and details=true for a project overview."
  end

  @impl true
  def parameters do
    %{
      "type" => "object",
      "properties" => %{
        "path" => %{
          "type" => "string",
          "description" => "Directory path (relative to workspace, or absolute)"
        },
        "recursive" => %{
          "type" => "boolean",
          "description" => "List nested directories recursively (default: false)"
        },
        "details" => %{
          "type" => "boolean",
          "description" => "Include file sizes and binary/build markers (default: false)"
        }
      },
      "required" => []
    }
  end

  @impl true
  def execute(args, _context) do
    path = Map.get(args, "path", ".")
    recursive = Map.get(args, "recursive", false)
    details = Map.get(args, "details", false)

    case Workspace.resolve(path) do
      {:ok, resolved} ->
        entries = list_entries(resolved, recursive, details)
        {:ok, Enum.join(entries, "\n")}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp list_entries(root, recursive, details, prefix \\ "") do
    case File.ls(root) do
      {:ok, entries} ->
        entries
        |> Enum.reject(&skip?/1)
        |> Enum.sort()
        |> Enum.flat_map(fn entry ->
          full = Path.join(root, entry)
          rel = prefix <> entry

          cond do
            File.dir?(full) and recursive ->
              [format_entry(rel <> "/", full, details, true)] ++
                list_entries(full, recursive, details, rel <> "/")

            true ->
              [format_entry(rel, full, details, File.dir?(full))]
          end
        end)

      {:error, reason} ->
        ["Error: could not list #{root}: #{:file.format_error(reason)}"]
    end
  end

  defp skip?(name), do: name in @skipped_dirs

  defp format_entry(path, full, details, is_dir) do
    path = if is_dir, do: path <> "/", else: path
    kind = if is_dir, do: "[DIR]", else: "[FILE]"

    if details and not is_dir do
      size = file_size(full)
      size_str = "#{size}b"
      marker = file_marker(full, size)
      "#{kind} #{path} #{size_str} #{marker}"
    else
      "#{kind} #{path}"
    end
  end

  defp file_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} -> size
      _ -> 0
    end
  end

  defp file_marker(path, size) do
    ext = Path.extname(path) |> String.downcase()

    cond do
      ext in @binary_extensions -> "[binary]"
      size > 50_000 -> "[large]"
      true -> "[text]"
    end
  end
end
