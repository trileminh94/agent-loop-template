defmodule AgentLoop.MCP.Messages do
  @moduledoc """
  JSON-RPC message builders for MCP.
  """

  @protocol_version "2024-11-05"

  @doc "Build an initialize request."
  def initialize(id) do
    request(id, "initialize", %{
      "protocolVersion" => @protocol_version,
      "capabilities" => %{},
      "clientInfo" => %{
        "name" => "agent_loop",
        "version" => "0.2.0"
      }
    })
    |> encode()
  end

  @doc "Build the initialized notification."
  def initialized_notification do
    notification("notifications/initialized", %{}) |> encode()
  end

  @doc "Build a tools/list request."
  def tools_list(id) do
    request(id, "tools/list", %{}) |> encode()
  end

  @doc "Build a tools/call request."
  def tools_call(id, name, args) do
    request(id, "tools/call", %{
      "name" => name,
      "arguments" => args
    })
    |> encode()
  end

  defp request(id, method, params) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "method" => method,
      "params" => params
    }
  end

  defp notification(method, params) do
    %{
      "jsonrpc" => "2.0",
      "method" => method,
      "params" => params
    }
  end

  defp encode(map) do
    Jason.encode!(map) <> "\n"
  end
end
