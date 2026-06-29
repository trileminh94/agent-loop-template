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
          "description" => "Command to run. No shell metacharacters are interpreted."
        },
        "args" => %{
          "type" => "array",
          "items" => %{"type" => "string"},
          "description" => "Arguments for the command"
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
  def execute(args) do
    command = Map.get(args, "command")
    cmd_args = Map.get(args, "args", [])
    timeout = Map.get(args, "timeout", @default_timeout_ms)

    cond do
      is_nil(command) or command == "" ->
        {:error, "missing required argument: command"}

      denied?(command) ->
        {:error, "command '#{command}' is not allowed"}

      true ->
        case Workspace.resolve(".") do
          {:ok, cwd} ->
            run(command, cmd_args, cwd, timeout)

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp denied?(command) do
    Enum.any?(@deny_patterns, &Regex.match?(&1, command))
  end

  defp run(command, args, cwd, timeout) do
    executable = System.find_executable(command)

    if is_nil(executable) do
      {:error, "command not found: #{command}"}
    else
      task = Task.async(fn -> System.cmd(executable, args, cd: cwd, stderr_to_stdout: true) end)

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
