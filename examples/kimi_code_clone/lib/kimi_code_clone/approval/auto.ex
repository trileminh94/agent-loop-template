defmodule KimiCodeClone.Approval.Auto do
  @moduledoc """
  Non-interactive approval for autonomous runs.

  Allows safe read/build/run commands and denies obviously destructive ones.
  Write_file is allowed only inside the workspace temp folder.
  """

  @behaviour AgentLoop.Approval

  alias AgentLoop.ToolCall
  alias AgentLoop.Tools.ShellExec

  @impl true
  def requires_approval?(%ToolCall{name: "shell_exec", arguments: args}, _context) do
    args |> Map.get("command", "") |> ShellExec.dangerous?()
  end

  def requires_approval?(%ToolCall{name: "write_file", arguments: args}, _context) do
    not inside_temp?(Map.get(args, "path", ""))
  end

  def requires_approval?(_tool_call, _context), do: false

  @impl true
  def approve(%ToolCall{name: "shell_exec", arguments: args}, _context) do
    command = Map.get(args, "command", "")

    if ShellExec.dangerous?(command) do
      {:error, "auto-denied dangerous command: #{command}"}
    else
      :ok
    end
  end

  def approve(%ToolCall{name: "write_file", arguments: args}, _context) do
    if inside_temp?(Map.get(args, "path", "")) do
      :ok
    else
      {:error, "auto-denied write outside temp folder"}
    end
  end

  def approve(_tool_call, _context), do: :ok

  defp inside_temp?(path) do
    workspace = Application.get_env(:kimi_code_clone, :workspace, File.cwd!())
    base = Path.expand("temp", workspace)
    expanded = Path.expand(path)
    String.starts_with?(expanded, base)
  end
end
