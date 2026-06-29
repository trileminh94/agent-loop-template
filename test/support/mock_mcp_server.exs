#!/usr/bin/env elixir
# A tiny MCP server used in tests.
# Handles only the JSON-RPC messages the test suite sends.

defmodule MockMCPServer do
  def run do
    loop()
  end

  defp loop do
    case IO.read(:line) do
      :eof ->
        :ok

      line ->
        respond(line)
        loop()
    end
  end

  defp respond(line) do
    id = extract_id(line)

    cond do
      String.contains?(line, "\"method\":\"initialize\"") ->
        IO.puts(
          ~s|{"id":#{id},"jsonrpc":"2.0","result":{"protocolVersion":"2024-11-05","capabilities":{},"serverInfo":{"name":"mock","version":"1.0.0"}}}|
        )

      String.contains?(line, "\"method\":\"tools/list\"") ->
        IO.puts(
          ~s|{"id":#{id},"jsonrpc":"2.0","result":{"tools":[{"name":"reverse","description":"Reverse a string","inputSchema":{"type":"object","properties":{"text":{"type":"string"}},"required":["text"]}}]}}|
        )

      String.contains?(line, "\"method\":\"tools/call\"") ->
        text = extract_text(line)
        reversed = String.reverse(text)

        IO.puts(
          ~s|{"id":#{id},"jsonrpc":"2.0","result":{"content":[{"type":"text","text":"#{escape(reversed)}"}]}}|
        )

      true ->
        :ok
    end
  end

  defp extract_id(line) do
    case Regex.run(~r/"id":(\d+)/, line) do
      [_, id] -> id
      _ -> "null"
    end
  end

  defp extract_text(line) do
    case Regex.run(~r/"text":"([^"]*)"/, line) do
      [_, text] -> text
      _ -> ""
    end
  end

  defp escape(string) do
    string
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
  end
end

MockMCPServer.run()
