defmodule AgentLoop.Support.MockTool do
  @moduledoc """
  Test tool that returns whatever it is configured to return.
  """

  @behaviour AgentLoop.Tool

  defstruct result: {:ok, "mock result"}

  @impl true
  def name, do: "mock_tool"

  @impl true
  def description, do: "A mock tool for tests."

  @impl true
  def parameters do
    %{
      "type" => "object",
      "properties" => %{},
      "required" => []
    }
  end

  @impl true
  def execute(_args) do
    # Tests override this via the configured result, but the behaviour expects
    # execute/1 without state. We use the process dictionary for test control.
    case Process.get(:mock_tool_result, {:ok, "mock result"}) do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  end
end
