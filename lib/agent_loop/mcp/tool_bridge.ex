defmodule AgentLoop.MCP.ToolBridge do
  @moduledoc """
  Converts MCP tool definitions into `AgentLoop.ToolDefinition` structs and
  provides helpers for name prefixing so MCP tools can coexist with native tools.
  """

  alias AgentLoop.ToolDefinition

  @prefix "mcp_"
  @separator "__"

  @doc "Return the prefix used for MCP tool names."
  def prefix, do: @prefix

  @doc """
  Build a prefixed tool name from a server name and an MCP tool name.

      iex> AgentLoop.MCP.ToolBridge.prefixed_name("filesystem", "read_file")
      "mcp_filesystem__read_file"
  """
  def prefixed_name(server_name, tool_name) do
    "#{@prefix}#{server_name}#{@separator}#{tool_name}"
  end

  @doc """
  Split a prefixed tool name back into `{server_name, tool_name}`.

  Returns `:error` if the name is not a prefixed MCP tool name.
  """
  def split_name(prefixed_name) when is_binary(prefixed_name) do
    prefix = @prefix
    separator = @separator

    with true <- String.starts_with?(prefixed_name, prefix),
         rest <- String.replace_prefix(prefixed_name, prefix, ""),
         [server_name, tool_name] <- String.split(rest, separator, parts: 2) do
      {:ok, server_name, tool_name}
    else
      _ -> :error
    end
  end

  @doc """
  Convert an MCP tool definition into an `AgentLoop.ToolDefinition`.
  """
  def to_definition(server_name, %{
        "name" => name,
        "description" => description,
        "inputSchema" => schema
      }) do
    %ToolDefinition{
      type: "function",
      function: %{
        name: prefixed_name(server_name, name),
        description: description,
        parameters: schema
      }
    }
  end

  def to_definition(server_name, %{
        "name" => name,
        "description" => description
      }) do
    %ToolDefinition{
      type: "function",
      function: %{
        name: prefixed_name(server_name, name),
        description: description,
        parameters: %{"type" => "object", "properties" => %{}}
      }
    }
  end

  @doc "Extract a plain-text result from an MCP tool call result."
  def extract_content(%{"content" => content}) when is_list(content) do
    content
    |> Enum.map(fn
      %{"type" => "text", "text" => text} -> text
      _ -> ""
    end)
    |> Enum.join("\n")
  end

  def extract_content(%{"content" => content}) when is_binary(content) do
    content
  end

  def extract_content(result) do
    inspect(result)
  end
end
