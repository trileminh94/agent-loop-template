defmodule AgentLoop.Tools.Echo do
  @moduledoc """
  Example tool that echoes back its input.
  Useful for testing the loop without side effects.
  """

  @behaviour AgentLoop.Tool

  @impl true
  def name, do: "echo"

  @impl true
  def description, do: "Echo the provided message back to the caller."

  @impl true
  def parameters do
    %{
      "type" => "object",
      "properties" => %{
        "message" => %{
          "type" => "string",
          "description" => "The message to echo"
        }
      },
      "required" => ["message"]
    }
  end

  @impl true
  def execute(%{"message" => message}, _context) do
    {:ok, "Echo: #{message}"}
  end

  def execute(_args, _context) do
    {:error, "missing required argument: message"}
  end
end
