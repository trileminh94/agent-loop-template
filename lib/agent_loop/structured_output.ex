defmodule AgentLoop.StructuredOutput do
  @moduledoc """
  Helpers for parsing and validating structured provider responses.

  These functions extract JSON (and optionally YAML) from assistant messages and
  validate the decoded value against a schema. They are intentionally small so
  consumers can layer more sophisticated validation on top.
  """

  alias AgentLoop.Message
  alias AgentLoop.Provider.Schema
  alias AgentLoop.ToolResult

  @doc """
  Parse the content of a message or response as JSON.

  Supports JSON wrapped in markdown code fences.
  """
  @spec parse_json(Schema.Response.t() | Message.t() | String.t() | nil) ::
          {:ok, any()} | {:error, any()}
  def parse_json(%Schema.Response{content: content}), do: parse_json(content)
  def parse_json(%Message{content: content}), do: parse_json(content)
  def parse_json(%ToolResult{content: content}), do: parse_json(content)

  def parse_json(content) when is_binary(content) do
    content
    |> strip_code_fence()
    |> Jason.decode()
  end

  def parse_json(nil), do: {:error, :empty_content}

  @doc """
  Parse the content of a message or response as JSON and validate it.

  `validator` is a 1-arity function that returns `{:ok, value}` or
  `{:error, reason}`.
  """
  @spec parse_json(Schema.Response.t() | Message.t() | String.t() | nil, function()) ::
          {:ok, any()} | {:error, any()}
  def parse_json(source, validator) when is_function(validator, 1) do
    with {:ok, data} <- parse_json(source) do
      validate(data, validator)
    end
  end

  @doc """
  Validate a decoded value against a custom validator function.

  The validator receives the decoded value and must return `{:ok, value}` or
  `{:error, reason}`.
  """
  @spec validate(any(), function()) :: {:ok, any()} | {:error, any()}
  def validate(data, validator) when is_function(validator, 1) do
    validator.(data)
  end

  @doc """
  Strip a markdown code fence from JSON or YAML content.
  """
  @spec strip_code_fence(String.t()) :: String.t()
  def strip_code_fence(content) do
    content
    |> String.replace(~r/^```(json|yaml|yml)?\s*/, "")
    |> String.replace(~r/\s*```$/, "")
    |> String.trim()
  end
end
