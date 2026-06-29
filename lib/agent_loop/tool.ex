defmodule AgentLoop.Tool do
  @moduledoc """
  Behaviour for tools that the agent loop can execute.

  ## Example

      defmodule MyApp.Tools.Calculator do
        @behaviour AgentLoop.Tool

        @impl true
        def name, do: "calculate"

        @impl true
        def description, do: "Evaluate a mathematical expression."

        @impl true
        def parameters do
          %{
            "type" => "object",
            "properties" => %{
              "expression" => %{
                "type" => "string",
                "description" => "Math expression to evaluate"
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
  """

  @callback name :: String.t()
  @callback description :: String.t()
  @callback parameters :: map()
  @callback execute(args :: map()) :: {:ok, any()} | {:error, any()}
end
