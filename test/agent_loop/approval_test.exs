defmodule AgentLoop.ApprovalTest do
  use ExUnit.Case, async: false

  alias AgentLoop.Approval.Terminal
  alias AgentLoop.Loop
  alias AgentLoop.LoopConfig
  alias AgentLoop.RunRequest
  alias AgentLoop.ToolCall
  alias AgentLoop.ToolRegistry
  alias AgentLoop.Tools.Context
  alias AgentLoop.Tools.ShellExec
  alias AgentLoop.Support.MockProvider

  test "ShellExec denies dangerous commands without approval" do
    assert {:error, "command 'rm -rf deps' is not allowed"} =
             ShellExec.execute(%{"command" => "rm -rf deps"}, %Context{})
  end

  test "ShellExec allows dangerous commands when context is approved" do
    assert {:ok, "hello\n"} =
             ShellExec.execute(%{"command" => "echo hello"}, %Context{approved: true})
  end

  test "Terminal approval requires approval for dangerous shell commands" do
    assert Terminal.requires_approval?(
             %ToolCall{name: "shell_exec", arguments: %{"command" => "rm -rf deps"}},
             %Context{}
           )
  end

  test "Terminal approval does not require approval for safe shell commands" do
    refute Terminal.requires_approval?(
             %ToolCall{name: "shell_exec", arguments: %{"command" => "ls"}},
             %Context{}
           )
  end

  test "Terminal approval denies on negative input" do
    tool_call = %ToolCall{name: "shell_exec", arguments: %{"command" => "rm -rf deps"}}

    assert {:error, "user denied shell_exec"} =
             with_input("n\n", fn ->
               Terminal.approve(tool_call, %Context{})
             end)
  end

  test "Terminal approval allows on positive input" do
    tool_call = %ToolCall{name: "shell_exec", arguments: %{"command" => "rm -rf deps"}}

    assert :ok =
             with_input("yes\n", fn ->
               Terminal.approve(tool_call, %Context{})
             end)
  end

  test "approval module short-circuits execution when denied" do
    defmodule AlwaysDeny do
      @behaviour AgentLoop.Approval

      @impl true
      def requires_approval?(_tool_call, _context), do: true

      @impl true
      def approve(_tool_call, _context), do: {:error, "denied by policy"}
    end

    provider = %MockProvider{
      responses: [
        %{tool_calls: [%ToolCall{id: "call-1", name: "echo", arguments: %{"message" => "hi"}}]},
        %{content: "done"}
      ]
    }

    registry = ToolRegistry.new() |> ToolRegistry.register(AgentLoop.Tools.Echo)

    config =
      LoopConfig.new(provider, registry,
        model: "mock",
        approval: AlwaysDeny
      )

    result = Loop.run(RunRequest.new("use echo"), config)

    assert result.content == "done"

    assert Enum.any?(result.messages, fn msg ->
             msg.role == :tool and msg.content == "Error: denied by policy"
           end)
  end

  defp with_input(input, fun) do
    {:ok, io} = StringIO.open(input)
    old_gl = Process.group_leader()
    Process.group_leader(self(), io)

    try do
      fun.()
    after
      Process.group_leader(self(), old_gl)
      StringIO.close(io)
    end
  end
end
