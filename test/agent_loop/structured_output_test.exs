defmodule AgentLoop.StructuredOutputTest do
  use ExUnit.Case, async: true

  alias AgentLoop.Provider.Schema
  alias AgentLoop.StructuredOutput

  describe "parse_json/1" do
    test "parses plain JSON" do
      assert {:ok, %{"answer" => 42}} = StructuredOutput.parse_json(~s({"answer": 42}))
    end

    test "strips markdown code fences" do
      content = """
      ```json
      {"answer": 42}
      ```
      """

      assert {:ok, %{"answer" => 42}} = StructuredOutput.parse_json(content)
    end

    test "parses JSON from a response struct" do
      response = %Schema.Response{content: ~s({"ok": true})}
      assert {:ok, %{"ok" => true}} = StructuredOutput.parse_json(response)
    end

    test "returns error for invalid JSON" do
      assert {:error, _} = StructuredOutput.parse_json("not json")
    end

    test "returns error for nil content" do
      assert {:error, :empty_content} = StructuredOutput.parse_json(nil)
    end
  end

  describe "parse_json/2 with validator function" do
    test "returns data when validator passes" do
      validator = fn data ->
        if is_map(data) and Map.has_key?(data, "answer"),
          do: {:ok, data},
          else: {:error, :missing_answer}
      end

      assert {:ok, %{"answer" => 42}} =
               StructuredOutput.parse_json(~s({"answer": 42}), validator)
    end

    test "returns error when validator fails" do
      validator = fn _data -> {:error, :rejected} end
      assert {:error, :rejected} = StructuredOutput.parse_json(~s({"x": 1}), validator)
    end
  end

  describe "validate/2" do
    test "uses custom validator function" do
      validator = fn data ->
        if is_map(data) and Map.get(data, "valid"),
          do: {:ok, data},
          else: {:error, :invalid}
      end

      assert {:ok, %{"valid" => true}} = StructuredOutput.validate(%{"valid" => true}, validator)
      assert {:error, :invalid} = StructuredOutput.validate(%{"valid" => false}, validator)
    end
  end
end
