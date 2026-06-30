defmodule AgentLoop.Tools.MCP do
  @moduledoc """
  Dispatcher for MCP tools.

  This module is registered once in the tool registry. The loop sets the
  active MCP client mapping in `AgentLoop.Tools.Context` before tool execution;
  when the model calls a prefixed MCP tool, this dispatcher routes the call to
  the right stdio client.
  """

  @behaviour AgentLoop.Tool

  alias AgentLoop.MCP.Client
  alias AgentLoop.MCP.ToolBridge

  @impl true
  def name, do: "__mcp_dispatcher__"

  @impl true
  def description, do: "Internal dispatcher for MCP tools."

  @impl true
  def parameters do
    %{
      "type" => "object",
      "properties" => %{},
      "required" => []
    }
  end

  @impl true
  def execute(_args, _context) do
    # args is ignored; the actual tool name is passed via the tool_call name.
    {:error, "mcp dispatcher must be called through the registry with a prefixed name"}
  end

  @doc "Execute an MCP tool by its prefixed name and arguments."
  def execute_prefixed(prefixed_name, args, context) do
    clients = Map.get(context || %{}, :mcp_clients, %{})

    with {:ok, server_name, tool_name} <- ToolBridge.split_name(prefixed_name),
         %Client{} = client <- Map.get(clients, server_name) do
      case Client.call_tool(client, tool_name, args) do
        {:ok, result} ->
          {:ok, ToolBridge.extract_content(result)}

        {:error, reason} ->
          {:error, "MCP tool failed: #{inspect(reason)}"}
      end
    else
      :error ->
        {:error, "invalid MCP tool name: #{prefixed_name}"}

      _ ->
        {:error, "MCP server not available for: #{prefixed_name}"}
    end
  end
end
