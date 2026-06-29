defmodule Mix.Tasks.Agent.RunTest do
  use ExUnit.Case, async: false

  alias AgentLoop.Tools.Workspace
  alias Mix.Tasks.Agent.Run, as: AgentRun

  setup do
    original_openai = System.get_env("OPENAI_API_KEY")
    original_deepseek = System.get_env("DEEPSEEK_API_KEY")

    System.delete_env("OPENAI_API_KEY")
    System.delete_env("DEEPSEEK_API_KEY")
    Workspace.reset()

    on_exit(fn ->
      if original_openai, do: System.put_env("OPENAI_API_KEY", original_openai)
      if original_deepseek, do: System.put_env("DEEPSEEK_API_KEY", original_deepseek)
      Workspace.reset()
    end)

    :ok
  end

  test "requires OPENAI_API_KEY by default" do
    assert_raise Mix.Error, "OPENAI_API_KEY is not set", fn ->
      AgentRun.run(["hello"])
    end
  end

  test "requires DEEPSEEK_API_KEY when provider is deepseek" do
    assert_raise Mix.Error, "DEEPSEEK_API_KEY is not set", fn ->
      AgentRun.run(["--provider", "deepseek", "hello"])
    end
  end
end
