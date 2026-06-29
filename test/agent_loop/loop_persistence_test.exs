defmodule AgentLoop.LoopPersistenceTest do
  use ExUnit.Case, async: false

  alias AgentLoop.Loop
  alias AgentLoop.LoopConfig
  alias AgentLoop.Persistence
  alias AgentLoop.Persistence.SQLite
  alias AgentLoop.RunRequest
  alias AgentLoop.ToolCall
  alias AgentLoop.ToolRegistry
  alias AgentLoop.Tools.Echo
  alias AgentLoop.Support.MockProvider

  setup do
    tmp = Path.join(System.tmp_dir!(), "agent_loop_persist_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    db = Path.join(tmp, "sessions.db")
    {:ok, persistence} = Persistence.new(SQLite, database: db)

    on_exit(fn ->
      File.rm_rf!(tmp)
    end)

    {:ok, persistence: persistence}
  end

  test "loads previous session history", %{persistence: persistence} do
    registry = ToolRegistry.new() |> ToolRegistry.register(Echo)

    provider = %MockProvider{
      responses: [
        %{content: "first reply"}
      ]
    }

    config =
      LoopConfig.new(provider, registry,
        model: "mock",
        persistence: persistence
      )

    # First run creates the session.
    request1 = RunRequest.new("hello", session_id: "session-1")
    result1 = Loop.run(request1, config)
    assert result1.content == "first reply"

    # Second run resumes and sees the previous user message.
    Process.delete({MockProvider, :index})

    provider2 = %MockProvider{
      responses: [
        %{content: "second reply"}
      ]
    }

    config2 =
      LoopConfig.new(provider2, registry,
        model: "mock",
        persistence: persistence
      )

    request2 = RunRequest.new("follow up", session_id: "session-1")
    result2 = Loop.run(request2, config2)
    assert result2.content == "second reply"

    # The final message list should include both user messages and both replies.
    assert length(result2.messages) == 4
  end

  test "writes traces when trace is enabled", %{persistence: {adapter, state} = persistence} do
    registry = ToolRegistry.new() |> ToolRegistry.register(Echo)

    provider = %MockProvider{
      responses: [
        %{tool_calls: [%ToolCall{id: "call-1", name: "echo", arguments: %{"message" => "x"}}]},
        %{content: "done"}
      ]
    }

    config =
      LoopConfig.new(provider, registry,
        model: "mock",
        persistence: persistence,
        trace: true
      )

    request = RunRequest.new("use tool", session_id: "session-trace", run_id: "run-trace")
    Loop.run(request, config)

    assert {:ok, traces} = adapter.get_trace(state, "session-trace", "run-trace")
    assert length(traces) >= 4
    assert Enum.any?(traces, &(&1.type == :tool_call))
    assert Enum.any?(traces, &(&1.type == :tool_result))
  end
end
