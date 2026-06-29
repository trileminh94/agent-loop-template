defmodule AgentLoop.Provider.OpenAICompatible do
  @moduledoc """
  Example OpenAI-compatible provider.

  Works with OpenAI, OpenRouter, Groq, DeepSeek, Gemini OpenAI-compatible
  endpoints, and any other provider that exposes `/chat/completions`.

  ## Usage

      provider = %AgentLoop.Provider.OpenAICompatible{
        api_key: System.get_env("OPENAI_API_KEY"),
        base_url: "https://api.openai.com/v1"
      }

  """

  @behaviour AgentLoop.Provider

  alias AgentLoop.Message
  alias AgentLoop.ToolCall

  defstruct api_key: nil,
            base_url: "https://api.openai.com/v1",
            http_options: [receive_timeout: 60_000]

  @type t :: %__MODULE__{
          api_key: String.t() | nil,
          base_url: String.t(),
          http_options: keyword()
        }

  @impl true
  def chat(%__MODULE__{} = provider, request) do
    url = "#{provider.base_url}/chat/completions"

    body =
      %{
        model: request.model,
        messages: Enum.map(request.messages, &to_openai_message/1),
        temperature: request.temperature
      }
      |> maybe_put(:max_tokens, request.max_tokens)
      |> maybe_put(:tools, format_tools(request[:tools]))

    headers = [
      {"authorization", "Bearer #{provider.api_key}"},
      {"content-type", "application/json"}
    ]

    opts = Keyword.merge([json: body, headers: headers], provider.http_options)

    case Req.post(url, opts) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        parse_response(body)

      {:ok, %{status: status, body: body}} ->
        {:error, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Serialization
  # ---------------------------------------------------------------------------

  defp to_openai_message(%Message{role: :assistant, content: content, tool_calls: nil}) do
    %{role: "assistant", content: content}
  end

  defp to_openai_message(%Message{role: :assistant, content: content, tool_calls: tool_calls}) do
    %{role: "assistant", content: content, tool_calls: Enum.map(tool_calls, &format_tool_call/1)}
  end

  defp to_openai_message(%Message{role: :tool, content: content, tool_call_id: id}) do
    %{role: "tool", content: content, tool_call_id: id}
  end

  defp to_openai_message(%Message{role: role, content: content}) do
    %{role: to_string(role), content: content}
  end

  defp format_tool_call(%ToolCall{id: id, name: name, arguments: args}) do
    %{
      id: id,
      type: "function",
      function: %{
        name: name,
        arguments: Jason.encode!(args)
      }
    }
  end

  defp format_tools(nil), do: nil
  defp format_tools([]), do: nil

  defp format_tools(tools) do
    Enum.map(tools, fn %{type: type, function: function} ->
      %{
        type: type,
        function: %{
          name: function.name,
          description: function.description,
          parameters: function.parameters
        }
      }
    end)
  end

  # ---------------------------------------------------------------------------
  # Parsing
  # ---------------------------------------------------------------------------

  defp parse_response(body) when is_map(body) do
    choice = List.first(body["choices"] || [])
    message = choice["message"] || %{}

    content = message["content"]
    tool_calls = parse_tool_calls(message["tool_calls"])
    finish_reason = choice["finish_reason"]
    usage = body["usage"]

    {:ok,
     %{
       content: content,
       tool_calls: tool_calls,
       finish_reason: finish_reason,
       usage: usage
     }}
  end

  defp parse_tool_calls(nil), do: nil
  defp parse_tool_calls([]), do: []

  defp parse_tool_calls(tool_calls) do
    Enum.map(tool_calls, fn tc ->
      function = tc["function"] || %{}

      arguments =
        case Jason.decode(function["arguments"] || "{}") do
          {:ok, args} -> args
          {:error, _} -> %{}
        end

      %ToolCall{
        id: tc["id"],
        name: function["name"],
        arguments: arguments,
        parse_error: nil
      }
    end)
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
