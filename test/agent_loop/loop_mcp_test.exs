defmodule AgentLoop.LoopMCPTest do
  use ExUnit.Case, async: false

  alias AgentLoop.Loop
  alias AgentLoop.LoopConfig
  alias AgentLoop.MCP.Server
  alias AgentLoop.ToolCall
  alias AgentLoop.ToolRegistry
  alias AgentLoop.Support.MockProvider

  setup do
    server = %Server{
      name: "mock",
      command: "elixir",
      args: [Path.join(__DIR__, "../support/mock_mcp_server.exs")],
      timeout: 10_000
    }

    {:ok, server: server}
  end

  test "discovers and calls an MCP tool", %{server: server} do
    registry = ToolRegistry.new()

    provider = %MockProvider{
      responses: [
        %{
          tool_calls: [
            %ToolCall{
              id: "call-1",
              name: "mcp_mock__reverse",
              arguments: %{"text" => "hello"}
            }
          ]
        },
        %{content: "done"}
      ]
    }

    config =
      LoopConfig.new(provider, registry,
        model: "mock",
        mcp_servers: [server]
      )

    request = AgentLoop.RunRequest.new("reverse hello")
    result = Loop.run(request, config)

    assert result.content == "done"
    assert result.total_tool_calls == 1

    assert Enum.any?(result.messages, fn msg ->
             msg.role == :tool and msg.content == "olleh"
           end)
  end
end
