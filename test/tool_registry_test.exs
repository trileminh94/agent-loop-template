defmodule AgentLoop.ToolRegistryTest do
  use ExUnit.Case, async: true

  alias AgentLoop.ToolRegistry
  alias AgentLoop.Tools.Echo

  describe "registration" do
    test "registers and resolves a tool" do
      registry = ToolRegistry.new() |> ToolRegistry.register(Echo)

      assert {:ok, Echo, "echo"} = ToolRegistry.resolve(registry, "echo")
      assert :error = ToolRegistry.resolve(registry, "missing")
    end

    test "registers multiple tools" do
      registry = ToolRegistry.new() |> ToolRegistry.register_many([Echo])

      assert [definition] = ToolRegistry.definitions(registry)
      assert definition.function.name == "echo"
    end

    test "supports aliases" do
      registry =
        ToolRegistry.new()
        |> ToolRegistry.register(Echo)
        |> ToolRegistry.register_alias("repeat", "echo")

      assert {:ok, Echo, "echo"} = ToolRegistry.resolve(registry, "repeat")
    end

    test "aliases do not shadow real tools" do
      registry =
        ToolRegistry.new()
        |> ToolRegistry.register(Echo)
        |> ToolRegistry.register_alias("echo", "other")

      assert {:ok, Echo, "echo"} = ToolRegistry.resolve(registry, "echo")
    end
  end

  describe "filtering" do
    test "allow list filters definitions" do
      registry = ToolRegistry.new() |> ToolRegistry.register(Echo)

      assert [] = ToolRegistry.definitions(registry, allow: ["other"])
      assert [_] = ToolRegistry.definitions(registry, allow: ["echo"])
    end

    test "deny list excludes definitions" do
      registry = ToolRegistry.new() |> ToolRegistry.register(Echo)

      assert [] = ToolRegistry.definitions(registry, deny: ["echo"])
      assert [_] = ToolRegistry.definitions(registry, deny: ["other"])
    end
  end

  describe "execution" do
    test "executes a known tool" do
      registry = ToolRegistry.new() |> ToolRegistry.register(Echo)
      result = ToolRegistry.execute(registry, "call-1", "echo", %{"message" => "hello"})

      assert result.name == "echo"
      assert result.content == "Echo: hello"
      refute result.is_error
    end

    test "returns error for unknown tool" do
      registry = ToolRegistry.new()
      result = ToolRegistry.execute(registry, "call-1", "missing", %{})

      assert result.is_error
      assert result.content =~ "unknown tool"
    end

    test "catches tool crashes" do
      defmodule Crasher do
        @behaviour AgentLoop.Tool
        def name, do: "crasher"
        def description, do: "crashes"
        def parameters, do: %{"type" => "object", "properties" => %{}}
        def execute(_args), do: raise("boom")
      end

      registry = ToolRegistry.new() |> ToolRegistry.register(Crasher)
      result = ToolRegistry.execute(registry, "call-1", "crasher", %{})

      assert result.is_error
      assert result.content =~ "crashed"
    end
  end

  describe "prefix stripping" do
    test "strips configured prefix" do
      assert "echo" = ToolRegistry.strip_prefix("tools_echo", "tools_")
      assert "echo" = ToolRegistry.strip_prefix("echo", "tools_")
    end
  end
end
