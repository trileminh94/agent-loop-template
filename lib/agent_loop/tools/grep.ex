defmodule AgentLoop.Tools.Grep do
  @moduledoc """
  Search file contents in the workspace.

  Uses ripgrep (`rg`) when available for speed, with a pure-Elixir fallback.
  """

  @behaviour AgentLoop.Tool

  alias AgentLoop.Tools.Workspace

  @impl true
  def name, do: "grep"

  @impl true
  def description do
    "Search for a pattern in workspace files. Returns matching lines with file paths and line numbers."
  end

  @impl true
  def parameters do
    %{
      "type" => "object",
      "properties" => %{
        "pattern" => %{
          "type" => "string",
          "description" => "Text or regex pattern to search for"
        },
        "path" => %{
          "type" => "string",
          "description" =>
            "Directory or file to search in (relative to workspace). Defaults to workspace root."
        },
        "glob" => %{
          "type" => "string",
          "description" => "Optional glob filter, e.g. '*.ex'"
        }
      },
      "required" => ["pattern"]
    }
  end

  @impl true
  def execute(args) do
    pattern = Map.get(args, "pattern")
    path = Map.get(args, "path", ".")
    glob = Map.get(args, "glob")

    if is_nil(pattern) or pattern == "" do
      {:error, "missing required argument: pattern"}
    else
      case Workspace.resolve(path) do
        {:ok, resolved} ->
          if System.find_executable("rg") do
            run_ripgrep(resolved, pattern, glob)
          else
            run_elixir_grep(resolved, pattern, glob)
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp run_ripgrep(resolved, pattern, glob) do
    args = ["--line-number", "--with-filename", "--color", "never", pattern, "."]
    args = if glob, do: ["--glob", glob | args], else: args

    case System.cmd("rg", args, cd: resolved, stderr_to_stdout: true) do
      {output, 0} -> {:ok, trim_output(output)}
      {output, _} -> {:ok, trim_output(output)}
    end
  end

  defp run_elixir_grep(resolved, pattern, glob) do
    regex = Regex.compile!(pattern)
    files = list_text_files(resolved, glob)

    matches =
      files
      |> Task.async_stream(&grep_file(&1, regex, resolved), ordered: false)
      |> Enum.flat_map(fn {:ok, result} -> result end)

    if matches == [] do
      {:ok, "No matches found."}
    else
      {:ok, Enum.join(matches, "\n")}
    end
  end

  defp grep_file(file, regex, root) do
    file
    |> File.stream!()
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      if Regex.match?(regex, line) do
        rel = Path.relative_to(file, root)
        ["#{rel}:#{line_no}: #{String.trim_trailing(line, "\n")}"]
      else
        []
      end
    end)
  end

  defp list_text_files(root, glob) do
    pattern = if glob, do: glob, else: "**/*"

    Path.wildcard(Path.join(root, pattern))
    |> Enum.filter(&File.regular?/1)
    |> Enum.reject(&binary_file?/1)
  end

  defp binary_file?(path) do
    ext = Path.extname(path) |> String.downcase()
    ext in [".exe", ".dll", ".so", ".dylib", ".jpg", ".jpeg", ".png", ".gif", ".mp3", ".mp4"]
  end

  defp trim_output(output) do
    output
    |> String.trim_trailing("\n")
    |> String.split("\n")
    |> Enum.take(200)
    |> Enum.join("\n")
  end
end
