defmodule AgentLoop.Approval.Terminal do
  @moduledoc """
  Interactive terminal approval.

  Prompts the user on stdin for tool calls that look destructive:

    * `shell_exec` commands matching the deny list in `AgentLoop.Tools.ShellExec`
    * `write_file` calls that overwrite an existing file

  ## Example

      config = AgentLoop.LoopConfig.new(provider, registry,
        approval: AgentLoop.Approval.Terminal
      )
  """

  @behaviour AgentLoop.Approval

  alias AgentLoop.ToolCall
  alias AgentLoop.Tools.ShellExec

  @impl true
  def requires_approval?(%ToolCall{name: "shell_exec", arguments: args}, _context) do
    command = Map.get(args, "command", "")
    ShellExec.dangerous?(command)
  end

  def requires_approval?(%ToolCall{name: "write_file", arguments: args}, _context) do
    path = Map.get(args, "path", "")
    path != "" and File.exists?(path)
  end

  def requires_approval?(_tool_call, _context), do: false

  @impl true
  def approve(tool_call, _context) do
    IO.puts("\n--- Approval required ---")
    IO.puts("Tool: #{tool_call.name}")
    IO.puts("Arguments:")
    IO.puts(Jason.encode!(tool_call.arguments, pretty: true))
    IO.write("Approve? (y/N) ")

    case IO.gets("") do
      :eof ->
        {:error, "user denied #{tool_call.name}"}

      input ->
        if String.downcase(String.trim(input)) in ["y", "yes"] do
          :ok
        else
          {:error, "user denied #{tool_call.name}"}
        end
    end
  end
end
