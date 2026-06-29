defmodule AgentLoop.Provider.DeepSeekTest do
  use ExUnit.Case, async: true

  alias AgentLoop.Provider.DeepSeek

  test "defaults to DeepSeek base URL" do
    provider = %DeepSeek{}
    assert provider.base_url == "https://api.deepseek.com"
  end

  test "is an AgentLoop.Provider" do
    assert function_exported?(DeepSeek, :chat, 2)
  end
end
