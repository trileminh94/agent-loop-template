defmodule AgentLoopTest do
  use ExUnit.Case, async: true

  alias AgentLoop.ToolRegistry
  alias AgentLoop.Tools.Echo
  alias AgentLoop.Tools.ReadFile
  alias AgentLoop.Support.MockProvider

  test "public API runs a loop end-to-end" do
    provider = %MockProvider{responses: [%{content: "hello"}]}

    registry =
      ToolRegistry.new()
      |> ToolRegistry.register_many([Echo, ReadFile])

    config =
      AgentLoop.LoopConfig.new(provider, registry,
        model: "mock",
        system_prompt: "You are helpful."
      )

    request = AgentLoop.RunRequest.new("hi")
    result = AgentLoop.run(request, config)

    assert result.content == "hello"
  end

  test "public API with event callback" do
    provider = %MockProvider{responses: [%{content: "hello"}]}
    registry = ToolRegistry.new() |> ToolRegistry.register(Echo)

    config =
      AgentLoop.LoopConfig.new(provider, registry, model: "mock")

    request = AgentLoop.RunRequest.new("hi")

    result =
      AgentLoop.run(request, config, fn event ->
        send(self(), {:event, event.type})
      end)

    assert result.content == "hello"
    assert_received {:event, :run_started}
    assert_received {:event, :run_completed}
  end
end
