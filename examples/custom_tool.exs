# Run with: mix run examples/custom_tool.exs
#
# Shows how to add a custom tool to the registry.

alias AgentLoop.ToolRegistry

defmodule Examples.Tools.Calculator do
  @behaviour AgentLoop.Tool

  @impl true
  def name, do: "calculate"

  @impl true
  def description, do: "Evaluate a basic math expression."

  @impl true
  def parameters do
    %{
      "type" => "object",
      "properties" => %{
        "expression" => %{
          "type" => "string",
          "description" => "Math expression like '2 + 2'"
        }
      },
      "required" => ["expression"]
    }
  end

  @impl true
  def execute(%{"expression" => expr}) do
    case Code.eval_string(expr) do
      {result, _} -> {:ok, to_string(result)}
      _ -> {:error, "invalid expression"}
    end
  end
end

Application.ensure_all_started(:agent_loop)

provider = %AgentLoop.Provider.OpenAICompatible{
  api_key: System.get_env("OPENAI_API_KEY"),
  base_url: "https://api.openai.com/v1"
}

registry =
  ToolRegistry.new()
  |> ToolRegistry.register(Examples.Tools.Calculator)

config =
  AgentLoop.LoopConfig.new(provider, registry,
    model: "gpt-4o-mini",
    system_prompt: "Use the calculate tool for math."
  )

request = AgentLoop.RunRequest.new("What is 13 * 27?")
result = AgentLoop.run(request, config)

IO.puts(result.content)
