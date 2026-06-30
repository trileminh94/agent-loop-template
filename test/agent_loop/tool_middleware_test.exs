defmodule AgentLoop.ToolMiddlewareTest do
  use ExUnit.Case, async: true

  alias AgentLoop.ToolMiddleware
  alias AgentLoop.ToolRegistry
  alias AgentLoop.Tools.Echo

  defmodule ArgumentLogger do
    @behaviour ToolMiddleware

    @impl true
    def before_execute(tool_call, _context) do
      send(self(), {:before, tool_call.name, tool_call.arguments})
      {:ok, tool_call}
    end

    @impl true
    def after_execute(result, _tool_call, _context) do
      send(self(), {:after, result.name, result.content})
      result
    end
  end

  defmodule ArgumentTransformer do
    @behaviour ToolMiddleware

    @impl true
    def before_execute(tool_call, _context) do
      new_args = Map.put(tool_call.arguments, "message", "transformed")
      {:ok, %{tool_call | arguments: new_args}}
    end

    @impl true
    def after_execute(result, _tool_call, _context) do
      %{result | content: result.content <> " [after]"}
    end
  end

  defmodule Rejector do
    @behaviour ToolMiddleware

    @impl true
    def before_execute(_tool_call, _context) do
      {:error, "rejected by middleware"}
    end

    @impl true
    def after_execute(result, _tool_call, _context), do: result
  end

  test "runs before and after middleware in order" do
    registry =
      ToolRegistry.new()
      |> ToolRegistry.register(Echo)
      |> ToolRegistry.add_middleware(ArgumentLogger)

    result = ToolRegistry.execute(registry, "call-1", "echo", %{"message" => "hi"})

    assert result.name == "echo"
    assert result.content == "Echo: hi"
    assert_received {:before, "echo", %{"message" => "hi"}}
    assert_received {:after, "echo", "Echo: hi"}
  end

  test "before middleware can transform arguments" do
    registry =
      ToolRegistry.new()
      |> ToolRegistry.register(Echo)
      |> ToolRegistry.add_middleware(ArgumentTransformer)

    result = ToolRegistry.execute(registry, "call-1", "echo", %{"message" => "hi"})

    assert result.content == "Echo: transformed [after]"
  end

  test "before middleware can short-circuit execution" do
    registry =
      ToolRegistry.new()
      |> ToolRegistry.register(Echo)
      |> ToolRegistry.add_middleware(Rejector)

    result = ToolRegistry.execute(registry, "call-1", "echo", %{"message" => "hi"})

    assert result.is_error
    assert result.content == "Error: rejected by middleware"
  end

  test "middleware preserves tool call id" do
    registry =
      ToolRegistry.new()
      |> ToolRegistry.register(Echo)
      |> ToolRegistry.add_middleware(ArgumentTransformer)

    result = ToolRegistry.execute(registry, "original-id", "echo", %{"message" => "hi"})

    assert result.tool_call_id == "original-id"
  end
end
