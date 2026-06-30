defmodule KimiCodeClone.Tools.Registry do
  @moduledoc """
  Builds the tool registry for Kimi Code Clone.

  Wraps destructive tools with approval prompts and keeps the rest as-is.
  """

  alias AgentLoop.ToolRegistry

  alias AgentLoop.Tools.{
    EditFile,
    FetchURL,
    Grep,
    ListFiles,
    Memory,
    ReadFile
  }

  alias KimiCodeClone.Tools.{ShellExec, WriteFile}

  def build do
    ToolRegistry.new()
    |> ToolRegistry.register_many([
      ReadFile,
      ListFiles,
      WriteFile,
      EditFile,
      Grep,
      ShellExec,
      FetchURL,
      Memory
    ])
  end
end
