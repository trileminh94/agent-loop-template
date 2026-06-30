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
  Parse the content of a message or response as YAML.

  A YAML parser module must be configured. The module must implement
  `decode!/1` (like `:yamerl`) or be passed as an option:

      AgentLoop.StructuredOutput.parse_yaml(response, yaml_parser: YamerlHelper)

  Without a parser, `{:error, :yaml_parser_not_configured}` is returned.
  """
  @spec parse_yaml(Schema.Response.t() | Message.t() | String.t() | nil, keyword()) ::
          {:ok, any()} | {:error, any()}
  def parse_yaml(%Schema.Response{content: content}, opts), do: parse_yaml(content, opts)
  def parse_yaml(%Message{content: content}, opts), do: parse_yaml(content, opts)
  def parse_yaml(%ToolResult{content: content}, opts), do: parse_yaml(content, opts)

  def parse_yaml(content, opts) when is_binary(content) do
    parser = opts[:yaml_parser] || Application.get_env(:agent_loop, :yaml_parser)

    if parser && Code.ensure_loaded?(parser) && function_exported?(parser, :decode!, 1) do
      try do
        data = parser.decode!(strip_code_fence(content))
        {:ok, data}
      rescue
        error -> {:error, Exception.message(error)}
      end
    else
      {:error, :yaml_parser_not_configured}
    end
  end

  def parse_yaml(nil, _opts), do: {:error, :empty_content}

  @doc """
  Parse the content of a message or response as YAML and validate it.
  """
  @spec parse_yaml(Schema.Response.t() | Message.t() | String.t() | nil, function(), keyword()) ::
          {:ok, any()} | {:error, any()}
  def parse_yaml(source, validator, opts) when is_function(validator, 1) do
    with {:ok, data} <- parse_yaml(source, opts) do
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
