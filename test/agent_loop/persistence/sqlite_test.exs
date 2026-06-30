defmodule AgentLoop.Persistence.SQLiteTest do
  use ExUnit.Case, async: false

  alias AgentLoop.Message
  alias AgentLoop.Persistence
  alias AgentLoop.Persistence.SQLite
  alias AgentLoop.ToolCall

  setup do
    tmp = Path.join(System.tmp_dir!(), "agent_loop_sqlite_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    db = Path.join(tmp, "test.db")
    {:ok, persistence} = Persistence.new(SQLite, database: db)

    on_exit(fn ->
      File.rm_rf!(tmp)
    end)

    {:ok, persistence: persistence}
  end

  test "saves and loads a session", %{persistence: {adapter, state}} do
    messages = [
      Message.user("hello"),
      Message.assistant("hi there")
    ]

    assert :ok = adapter.save_session(state, "session-1", messages, %{"title" => "Test"})

    assert {:ok, %{messages: loaded, metadata: %{"title" => "Test"}}} =
             adapter.load_session(state, "session-1")

    assert length(loaded) == 2
    assert hd(loaded).role == :user
  end

  test "lists sessions ordered by updated_at", %{persistence: {adapter, state}} do
    adapter.save_session(state, "a", [], %{"title" => "A"})
    adapter.save_session(state, "b", [], %{"title" => "B"})

    assert {:ok, sessions} = adapter.list_sessions(state, [])
    assert Enum.map(sessions, & &1.id) == ["b", "a"]
  end

  test "remembers and recalls notes", %{persistence: {adapter, state}} do
    assert :ok = adapter.remember(state, "session-1", "note one")
    assert :ok = adapter.remember(state, "session-1", "note two")

    assert {:ok, content} = adapter.recall(state, "session-1", [])
    assert content =~ "note one"
    assert content =~ "note two"
  end

  test "writes and reads traces", %{persistence: {adapter, state}} do
    assert :ok =
             adapter.write_trace(state, "session-1", "run-1", %{type: :thinking, payload: %{}})

    assert :ok =
             adapter.write_trace(state, "session-1", "run-1", %{
               type: :tool_call,
               payload: %{name: "read_file"}
             })

    assert {:ok, traces} = adapter.get_trace(state, "session-1", "run-1")
    assert length(traces) == 2
    assert Enum.at(traces, 1).type == :tool_call
  end

  test "round-trips messages with tool_calls", %{persistence: {adapter, state}} do
    messages = [
      Message.user("call a tool"),
      Message.assistant(nil,
        tool_calls: [
          %ToolCall{id: "call-1", name: "list_files", arguments: %{"path" => "."}}
        ]
      ),
      Message.tool("call-1", "a.txt\nb.txt")
    ]

    assert :ok = adapter.save_session(state, "session-tools", messages, %{})

    assert {:ok, %{messages: loaded}} = adapter.load_session(state, "session-tools")

    assert length(loaded) == 3

    assert [%ToolCall{} = tc] = Enum.at(loaded, 1).tool_calls
    assert tc.id == "call-1"
    assert tc.name == "list_files"
    assert tc.arguments == %{"path" => "."}
  end
end
