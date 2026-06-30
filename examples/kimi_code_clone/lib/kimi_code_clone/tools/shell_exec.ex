defmodule KimiCodeClone.Tools.ShellExec do
  @moduledoc """
  ShellExec wrapper that prompts for approval before running.
  """

  @behaviour AgentLoop.Tool

  alias AgentLoop.Tools.ShellExec, as: BaseTool
  alias KimiCodeClone.Approval

  @impl true
  def name, do: BaseTool.name()

  @impl true
  def description, do: BaseTool.description()

  @impl true
  def parameters, do: BaseTool.parameters()

  @impl true
  def execute(args, context) do
    if Approval.prompt(name(), args) do
      BaseTool.execute(args, context)
    else
      {:error, "user denied shell_exec"}
    end
  end
end
