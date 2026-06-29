defmodule AgentLoop.LoopTest do
  use ExUnit.Case, async: true

  alias AgentLoop.Loop
  alias AgentLoop.LoopConfig
  alias AgentLoop.RunRequest
  alias AgentLoop.ToolCall
  alias AgentLoop.ToolRegistry
  alias AgentLoop.Tools.Echo
  alias AgentLoop.Support.MockProvider

  defp build_config(provider, opts \\ []) do
    registry = ToolRegistry.new() |> ToolRegistry.register(Echo)

    LoopConfig.new(provider, registry,
      model: "mock-model",
      max_iterations: Keyword.get(opts, :max_iterations, 10),
      max_tool_calls: Keyword.get(opts, :max_tool_calls, 50),
      system_prompt: Keyword.get(opts, :system_prompt, "You are a test assistant."),
      event_callback: Keyword.get(opts, :event_callback)
    )
  end

  describe "without tools" do
    test "returns provider content directly" do
      provider = %MockProvider{responses: [%{content: "hello there"}]}
      config = build_config(provider)
      request = RunRequest.new("hi")

      result = Loop.run(request, config)

      assert result.content == "hello there"
      assert result.iterations == 1
      assert result.finish_reason == :complete
    end
  end

  describe "with tools" do
    test "executes a single tool and returns final content" do
      provider = %MockProvider{
        responses: [
          %{
            tool_calls: [
              %ToolCall{id: "call-1", name: "echo", arguments: %{"message" => "world"}}
            ]
          },
          %{content: "done echoing"}
        ]
      }

      config = build_config(provider)
      request = RunRequest.new("echo something")

      result = Loop.run(request, config)

      assert result.content == "done echoing"
      assert result.iterations == 2
      assert result.total_tool_calls == 1

      assert [_, _, assistant_msg, tool_msg] = result.messages
      assert assistant_msg.role == :assistant
      assert tool_msg.role == :tool
      assert tool_msg.content == "Echo: world"
    end

    test "executes multiple tools in parallel" do
      provider = %MockProvider{
        responses: [
          %{
            tool_calls: [
              %ToolCall{id: "call-1", name: "echo", arguments: %{"message" => "a"}},
              %ToolCall{id: "call-2", name: "echo", arguments: %{"message" => "b"}}
            ]
          },
          %{content: "done"}
        ]
      }

      config = build_config(provider)
      request = RunRequest.new("echo two things")

      result = Loop.run(request, config)

      assert result.content == "done"
      assert result.total_tool_calls == 2
    end

    test "stops at max iterations" do
      provider = %MockProvider{
        responses:
          Stream.cycle([
            %{tool_calls: [%ToolCall{id: "call-1", name: "echo", arguments: %{"message" => "x"}}]}
          ])
          |> Enum.take(20)
      }

      config = build_config(provider, max_iterations: 3)
      request = RunRequest.new("loop forever")

      result = Loop.run(request, config)

      assert result.finish_reason == :max_iterations
      assert result.iterations == 3
    end

    test "stops when tool budget exceeded" do
      provider = %MockProvider{
        responses: [
          %{
            tool_calls: [
              %ToolCall{id: "call-1", name: "echo", arguments: %{"message" => "a"}}
            ]
          },
          %{content: "summary"}
        ]
      }

      config = build_config(provider, max_tool_calls: 1)
      request = RunRequest.new("use tools")

      result = Loop.run(request, config)

      assert result.content == "summary"
      assert result.total_tool_calls == 1
    end
  end

  describe "events" do
    test "emits run lifecycle events" do
      provider = %MockProvider{responses: [%{content: "ok"}]}

      config =
        build_config(provider,
          event_callback: fn event ->
            send(self(), {:event, event.type})
          end
        )

      request = RunRequest.new("hi")
      Loop.run(request, config)

      assert_received {:event, :run_started}
      assert_received {:event, :thinking}
      assert_received {:event, :run_completed}
    end

    test "emits tool events" do
      provider = %MockProvider{
        responses: [
          %{tool_calls: [%ToolCall{id: "call-1", name: "echo", arguments: %{"message" => "x"}}]},
          %{content: "ok"}
        ]
      }

      config =
        build_config(provider,
          event_callback: fn event ->
            send(self(), {:event, event.type, event.payload})
          end
        )

      request = RunRequest.new("use tool")
      Loop.run(request, config)

      assert_received {:event, :tool_call, %{name: "echo"}}
      assert_received {:event, :tool_result, %{name: "echo"}}
    end
  end
end
