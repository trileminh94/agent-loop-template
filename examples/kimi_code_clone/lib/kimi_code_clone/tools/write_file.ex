defmodule KimiCodeClone.Tools.WriteFile do
  @moduledoc """
  WriteFile wrapper that prompts for approval before overwriting files.
  """

  @behaviour AgentLoop.Tool

  alias AgentLoop.Tools.WriteFile, as: BaseTool
  alias KimiCodeClone.Approval

  @impl true
  def name, do: BaseTool.name()

  @impl true
  def description, do: BaseTool.description()

  @impl true
  def parameters, do: BaseTool.parameters()

  @impl true
  def execute(args) do
    path = Map.get(args, "path")

    # No approval needed for new files.
    if File.exists?(path) do
      if Approval.prompt(name(), args) do
        BaseTool.execute(args)
      else
        {:error, "user denied write_file"}
      end
    else
      BaseTool.execute(args)
    end
  end
end
