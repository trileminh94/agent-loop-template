defmodule AgentLoop.LoopTest do
  use ExUnit.Case, async: true

  alias AgentLoop.Loop
  alias AgentLoop.LoopConfig
  alias AgentLoop.Message
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
      event_callback: Keyword.get(opts, :event_callback),
      stream: Keyword.get(opts, :stream, false)
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

      assert [_, _, assistant_msg, tool_msg, final_msg] = result.messages
      assert assistant_msg.role == :assistant
      assert tool_msg.role == :tool
      assert tool_msg.content == "Echo: world"
      assert final_msg.role == :assistant
      assert final_msg.content == "done echoing"
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

  describe "retries" do
    test "retries transient provider failures up to max_retries" do
      provider = %AgentLoop.Support.FlakyProvider{failures: 2, response: %{content: "ok"}}

      config =
        LoopConfig.new(provider, ToolRegistry.new(),
          model: "mock",
          max_retries: 3,
          retry_backoff_ms: 0
        )

      request = RunRequest.new("hi")
      result = Loop.run(request, config)

      assert result.content == "ok"
      assert result.finish_reason == :complete
    end

    test "gives up after max_retries" do
      provider = %AgentLoop.Support.FlakyProvider{failures: 5, response: %{content: "ok"}}

      config =
        LoopConfig.new(provider, ToolRegistry.new(),
          model: "mock",
          max_retries: 2,
          retry_backoff_ms: 0
        )

      request = RunRequest.new("hi")
      result = Loop.run(request, config)

      assert result.finish_reason == :error
    end

    test "respects retry_on predicate" do
      provider = %AgentLoop.Support.FlakyProvider{failures: 2, response: %{content: "ok"}}

      config =
        LoopConfig.new(provider, ToolRegistry.new(),
          model: "mock",
          max_retries: 3,
          retry_backoff_ms: 0,
          retry_on: fn reason -> reason == :should_retry end
        )

      request = RunRequest.new("hi")
      result = Loop.run(request, config)

      assert result.finish_reason == :error
    end
  end

  describe "truncation" do
    test "drops oldest messages on context-length error and retries" do
      provider = %AgentLoop.Support.ContextLengthProvider{response: %{content: "ok"}}

      config =
        LoopConfig.new(provider, ToolRegistry.new(),
          model: "mock",
          system_prompt: "You are helpful.",
          truncation_strategy: :drop_oldest,
          max_truncation_retries: 1,
          max_iterations: 5
        )

      request =
        RunRequest.new("hi", history: [Message.user("old"), Message.assistant("old reply")])

      result = Loop.run(request, config)

      assert result.content == "ok"
      assert result.finish_reason == :complete
    end

    test "fails when truncation retries are exhausted" do
      provider = %AgentLoop.Support.ContextLengthProvider{response: %{content: "ok"}}

      config =
        LoopConfig.new(provider, ToolRegistry.new(),
          model: "mock",
          system_prompt: "You are helpful.",
          truncation_strategy: :drop_oldest,
          max_truncation_retries: 0,
          max_iterations: 5
        )

      request =
        RunRequest.new("hi", history: [Message.user("old"), Message.assistant("old reply")])

      result = Loop.run(request, config)

      assert result.finish_reason == :error
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

  describe "streaming" do
    test "emits content deltas when stream is enabled" do
      provider = %MockProvider{responses: [%{content: "hello"}]}

      config =
        build_config(provider,
          stream: true,
          event_callback: fn event ->
            send(self(), {:event, event.type, event.payload})
          end
        )

      request = RunRequest.new("hi")
      result = Loop.run(request, config)

      assert result.content == "hello"
      assert_received {:event, :content_delta, %{content: "hello"}}
      assert_received {:event, :run_completed, _}
    end

    test "falls back to chat when provider does not implement chat_stream" do
      provider = %AgentLoop.Support.NonStreamingProvider{responses: [%{content: "ok"}]}

      config =
        LoopConfig.new(provider, ToolRegistry.new(),
          model: "mock",
          stream: true,
          event_callback: fn event ->
            send(self(), {:event, event.type, event.payload})
          end
        )

      request = RunRequest.new("hi")
      result = Loop.run(request, config)

      assert result.content == "ok"
      refute_received {:event, :content_delta, _}
    end
  end
end
