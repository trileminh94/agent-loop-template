defmodule AgentLoop.MCP.ClientTest do
  use ExUnit.Case, async: true

  alias AgentLoop.MCP.Client
  alias AgentLoop.MCP.Server

  setup do
    server = %Server{
      name: "mock",
      command: "elixir",
      args: [Path.join(__DIR__, "../../support/mock_mcp_server.exs")],
      timeout: 10_000
    }

    {:ok, server: server}
  end

  test "initializes and lists tools", %{server: server} do
    assert {:ok, client} = Client.start(server)
    assert {:ok, tools} = Client.list_tools(client)
    assert [%{"name" => "reverse"}] = tools
    assert :ok = Client.stop(client)
  end

  test "calls a tool", %{server: server} do
    assert {:ok, client} = Client.start(server)
    assert {:ok, result} = Client.call_tool(client, "reverse", %{"text" => "hello"})
    assert result["content"] == [%{"type" => "text", "text" => "olleh"}]
    assert :ok = Client.stop(client)
  end
end
