defmodule AgentLoop.MCP.ToolBridgeTest do
  use ExUnit.Case, async: true

  alias AgentLoop.MCP.ToolBridge

  test "prefixed_name and split_name are inverse" do
    prefixed = ToolBridge.prefixed_name("filesystem", "read_file")
    assert prefixed == "mcp_filesystem__read_file"
    assert {:ok, "filesystem", "read_file"} = ToolBridge.split_name(prefixed)
  end

  test "split_name returns error for non-prefixed names" do
    assert :error = ToolBridge.split_name("read_file")
    assert :error = ToolBridge.split_name("mcp_read_file")
  end

  test "to_definition converts MCP tool schema" do
    tool = %{
      "name" => "reverse",
      "description" => "Reverse a string",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{"text" => %{"type" => "string"}},
        "required" => ["text"]
      }
    }

    definition = ToolBridge.to_definition("mock", tool)
    assert definition.function.name == "mcp_mock__reverse"
    assert definition.function.description == "Reverse a string"
    assert definition.function.parameters["type"] == "object"
  end

  test "extract_content handles text content list" do
    result = %{"content" => [%{"type" => "text", "text" => "hello"}]}
    assert ToolBridge.extract_content(result) == "hello"
  end
end
