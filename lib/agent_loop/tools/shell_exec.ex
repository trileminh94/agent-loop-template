defmodule AgentLoop.Tools.ShellExec do
  @moduledoc """
  Execute a shell command inside the workspace.

  This is a powerful tool. It runs commands directly without a shell wrapper,
  which avoids metacharacter injection, but still allows arbitrary code
  execution. Restrict the workspace and review command output carefully.

  Inspired by goclaw's exec tool, but minimal: no sandbox, no approval flow.
  """

  @behaviour AgentLoop.Tool

  alias AgentLoop.Tools.Workspace

  @default_timeout_ms 30_000
  @max_output_bytes 50_000

  @deny_patterns [
    ~r/^rm\s+/,
    ~r/^mkfs/,
    ~r/^dd\s+/,
    ~r/>\s*\/dev\//,
    ~r/:(){ :|:& };:/
  ]

  @impl true
  def name, do: "shell_exec"

  @impl true
  def description do
    "Run a shell command in the workspace. Output is capped at #{div(@max_output_bytes, 1000)} KB."
  end

  @impl true
  def parameters do
    %{
      "type" => "object",
      "properties" => %{
        "command" => %{
          "type" => "string",
          "description" =>
            "Command to run. Can be a full string (e.g. 'mkdir -p dir') when args is omitted, or just the executable name when args is provided."
        },
        "args" => %{
          "type" => "array",
          "items" => %{"type" => "string"},
          "description" =>
            "Arguments for the command. Omit if the command already contains arguments."
        },
        "timeout" => %{
          "type" => "integer",
          "description" => "Timeout in milliseconds (default: #{@default_timeout_ms})"
        }
      },
      "required" => ["command"]
    }
  end

  @impl true
  def execute(args, %{approved: true} = context) do
    execute_approved(args, context)
  end

  def execute(args, context) do
    command = Map.get(args, "command")

    cond do
      is_nil(command) or command == "" ->
        {:error, "missing required argument: command"}

      denied?(command) ->
        {:error, "command '#{command}' is not allowed"}

      true ->
        execute_approved(args, context)
    end
  end

  @doc """
  Execute a command without the deny-list check.

  Use this when an interactive approval layer (e.g. KimiCodeClone) has already
  asked the user and wants to run the command anyway.
  """
  def execute_approved(args, _context) do
    command = Map.get(args, "command")
    cmd_args = Map.get(args, "args", [])
    timeout = Map.get(args, "timeout", @default_timeout_ms)

    {executable, argv} = parse_command(command, cmd_args)

    case Workspace.resolve(".") do
      {:ok, cwd} ->
        run(executable, argv, cwd, timeout)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Return true if the command matches the deny list."
  def dangerous?(command) when is_binary(command) do
    denied?(command)
  end

  defp parse_command(command, args) when is_list(args) and length(args) > 0 do
    {command, args}
  end

  defp parse_command(command, _args) do
    parts = String.split(command)

    case parts do
      [exe | argv] -> {exe, argv}
      [] -> {command, []}
    end
  end

  defp denied?(command) do
    Enum.any?(@deny_patterns, &Regex.match?(&1, command))
  end

  defp run(executable, args, cwd, timeout) do
    found = System.find_executable(executable)

    if is_nil(found) do
      {:error, "command not found: #{executable}"}
    else
      task = Task.async(fn -> System.cmd(found, args, cd: cwd, stderr_to_stdout: true) end)

      try do
        case Task.await(task, timeout) do
          {output, 0} ->
            {:ok, cap(output)}

          {output, exit_code} ->
            {:error, "exit #{exit_code}\n#{cap(output)}"}
        end
      catch
        :exit, {:timeout, _} ->
          Task.shutdown(task, :brutal_kill)
          {:error, "command timed out after #{timeout}ms"}
      end
    end
  end

  defp cap(output) do
    if byte_size(output) > @max_output_bytes do
      String.slice(output, 0, @max_output_bytes) <> "\n... (output truncated)"
    else
      output
    end
  end
end
