defmodule KimiCodeClone.Tools.Registry do
  @moduledoc """
  Builds the tool registry for Kimi Code Clone.
  """

  alias AgentLoop.ToolRegistry

  alias AgentLoop.Tools.{
    EditFile,
    FetchURL,
    Grep,
    ListFiles,
    Memory,
    ReadFile,
    ReadFiles,
    ShellExec,
    WriteFile
  }

  def build do
    ToolRegistry.new()
    |> ToolRegistry.register_many([
      ReadFile,
      ReadFiles,
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
