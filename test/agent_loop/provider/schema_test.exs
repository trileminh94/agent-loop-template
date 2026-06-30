defmodule AgentLoop.Provider.SchemaTest do
  use ExUnit.Case, async: true

  alias AgentLoop.Message
  alias AgentLoop.Provider.OpenAICompatible
  alias AgentLoop.Provider.Schema
  alias AgentLoop.ToolCall
  alias AgentLoop.ToolDefinition

  describe "request serialization" do
    test "converts a normalized request to OpenAI format" do
      request = %Schema.Request{
        model: "gpt-4o-mini",
        messages: [
          Message.system("You are helpful."),
          Message.user("Hello")
        ],
        temperature: 0.7,
        max_tokens: 100
      }

      body = OpenAICompatible.to_openai_request(request)

      assert body.model == "gpt-4o-mini"
      assert body.temperature == 0.7
      assert body.max_tokens == 100

      assert body.messages == [
               %{role: "system", content: "You are helpful."},
               %{role: "user", content: "Hello"}
             ]
    end

    test "converts assistant messages with tool calls" do
      request = %Schema.Request{
        model: "mock",
        messages: [
          Message.assistant(nil,
            tool_calls: [
              %ToolCall{id: "call-1", name: "echo", arguments: %{"message" => "hi"}}
            ]
          )
        ]
      }

      body = OpenAICompatible.to_openai_request(request)

      assert body.messages == [
               %{
                 role: "assistant",
                 content: nil,
                 tool_calls: [
                   %{
                     id: "call-1",
                     type: "function",
                     function: %{
                       name: "echo",
                       arguments: ~s({"message":"hi"})
                     }
                   }
                 ]
               }
             ]
    end

    test "converts tool result messages" do
      request = %Schema.Request{
        model: "mock",
        messages: [
          Message.tool("call-1", "result", name: "echo")
        ]
      }

      body = OpenAICompatible.to_openai_request(request)

      assert body.messages == [
               %{role: "tool", content: "result", tool_call_id: "call-1"}
             ]
    end

    test "omits nil optional fields" do
      request = %Schema.Request{
        model: "mock",
        messages: [Message.user("hi")],
        temperature: nil,
        max_tokens: nil,
        tools: nil
      }

      body = OpenAICompatible.to_openai_request(request)

      refute Map.has_key?(body, :temperature)
      refute Map.has_key?(body, :max_tokens)
      refute Map.has_key?(body, :tools)
    end

    test "converts tool definitions" do
      tool = %ToolDefinition{
        type: "function",
        function: %{
          name: "echo",
          description: "Echoes input.",
          parameters: %{
            type: "object",
            properties: %{"message" => %{type: "string"}},
            required: ["message"]
          }
        }
      }

      request = %Schema.Request{
        model: "mock",
        messages: [Message.user("hi")],
        tools: [tool]
      }

      body = OpenAICompatible.to_openai_request(request)

      assert body.tools == [
               %{
                 type: "function",
                 function: %{
                   name: "echo",
                   description: "Echoes input.",
                   parameters: tool.function.parameters
                 }
               }
             ]
    end
  end

  describe "response parsing" do
    test "parses a simple assistant response" do
      body = %{
        "choices" => [
          %{
            "message" => %{"role" => "assistant", "content" => "hello"},
            "finish_reason" => "stop"
          }
        ],
        "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 5}
      }

      assert {:ok, %Schema.Response{} = response} = OpenAICompatible.from_openai_response(body)

      assert response.content == "hello"
      assert response.finish_reason == "stop"
      assert response.tool_calls == nil
      assert response.usage == %{"prompt_tokens" => 10, "completion_tokens" => 5}
    end

    test "parses a response with tool calls" do
      body = %{
        "choices" => [
          %{
            "message" => %{
              "role" => "assistant",
              "content" => nil,
              "tool_calls" => [
                %{
                  "id" => "call-1",
                  "type" => "function",
                  "function" => %{
                    "name" => "echo",
                    "arguments" => ~s({"message":"hi"})
                  }
                }
              ]
            },
            "finish_reason" => "tool_calls"
          }
        ]
      }

      assert {:ok, %Schema.Response{} = response} = OpenAICompatible.from_openai_response(body)

      assert response.content == nil
      assert response.finish_reason == "tool_calls"

      assert [
               %ToolCall{
                 id: "call-1",
                 name: "echo",
                 arguments: %{"message" => "hi"}
               }
             ] = response.tool_calls
    end

    test "returns empty tool call list when tool_calls is empty" do
      body = %{
        "choices" => [
          %{
            "message" => %{"content" => "done", "tool_calls" => []},
            "finish_reason" => "stop"
          }
        ]
      }

      assert {:ok, %Schema.Response{} = response} = OpenAICompatible.from_openai_response(body)
      assert response.tool_calls == []
    end
  end

  describe "round-trip" do
    test "tool call arguments survive encoding and decoding" do
      original = %ToolCall{
        id: "call-abc",
        name: "calculate",
        arguments: %{"expression" => "2 + 2", "precision" => 2}
      }

      request = %Schema.Request{
        model: "mock",
        messages: [Message.assistant(nil, tool_calls: [original])]
      }

      body = OpenAICompatible.to_openai_request(request)
      [tool_call] = hd(body.messages).tool_calls

      response_body = %{
        "choices" => [
          %{
            "message" => %{
              "content" => nil,
              "tool_calls" => [
                %{
                  "id" => tool_call.id,
                  "type" => tool_call.type,
                  "function" => %{
                    "name" => tool_call.function.name,
                    "arguments" => tool_call.function.arguments
                  }
                }
              ]
            },
            "finish_reason" => "tool_calls"
          }
        ]
      }

      assert {:ok, %Schema.Response{} = response} =
               OpenAICompatible.from_openai_response(response_body)

      assert [round_tripped] = response.tool_calls
      assert round_tripped.id == original.id
      assert round_tripped.name == original.name
      assert round_tripped.arguments == original.arguments
    end
  end
end
