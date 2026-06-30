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
  alias AgentLoop.Provider.Schema
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
  def chat(%__MODULE__{} = provider, %Schema.Request{} = request) do
    url = "#{provider.base_url}/chat/completions"

    headers = [
      {"authorization", "Bearer #{provider.api_key}"},
      {"content-type", "application/json"}
    ]

    opts =
      Keyword.merge([json: to_openai_request(request), headers: headers], provider.http_options)

    case Req.post(url, opts) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        from_openai_response(body)

      {:ok, %{status: status, body: body}} ->
        {:error, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def chat_stream(%__MODULE__{} = provider, %Schema.Request{} = request, callback)
      when is_function(callback, 1) do
    url = "#{provider.base_url}/chat/completions"

    headers = [
      {"authorization", "Bearer #{provider.api_key}"},
      {"content-type", "application/json"}
    ]

    body = Map.put(to_openai_request(request), :stream, true)

    acc = %{
      buffer: "",
      content: "",
      tool_calls: %{},
      finish_reason: nil
    }

    opts =
      Keyword.merge(
        [
          json: body,
          headers: headers,
          into: fn {:data, data}, {req, resp} ->
            acc = parse_stream_chunk(data, resp.body || acc, callback)
            {:cont, {req, %{resp | body: acc}}}
          end
        ],
        provider.http_options
      )

    case Req.post(url, opts) do
      {:ok, %{status: status, body: acc}} when status in 200..299 ->
        {:ok, build_stream_response(acc)}

      {:ok, %{status: status, body: body}} ->
        {:error, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Provider adapter functions
  # ---------------------------------------------------------------------------

  @doc """
  Convert a normalized `Schema.Request` into an OpenAI-compatible request body.
  """
  @spec to_openai_request(Schema.Request.t()) :: map()
  def to_openai_request(%Schema.Request{} = request) do
    %{
      model: request.model,
      messages: Enum.map(request.messages, &to_openai_message/1)
    }
    |> maybe_put(:temperature, request.temperature)
    |> maybe_put(:max_tokens, request.max_tokens)
    |> maybe_put(:tools, format_tools(request.tools))
  end

  @doc """
  Parse an OpenAI-compatible response body into a normalized `Schema.Response`.
  """
  @spec from_openai_response(map()) :: {:ok, Schema.Response.t()} | {:error, any()}
  def from_openai_response(body) when is_map(body) do
    choice = List.first(body["choices"] || [])
    message = choice["message"] || %{}

    content = message["content"]
    tool_calls = parse_tool_calls(message["tool_calls"])
    finish_reason = choice["finish_reason"]
    usage = body["usage"]

    {:ok,
     %Schema.Response{
       content: content,
       tool_calls: tool_calls,
       finish_reason: finish_reason,
       usage: usage
     }}
  end

  # ---------------------------------------------------------------------------
  # Streaming
  # ---------------------------------------------------------------------------

  defp parse_stream_chunk(chunk, acc, callback) do
    (acc.buffer <> chunk)
    |> String.split("\n\n")
    |> then(fn parts ->
      {buffer, complete} = List.pop_at(parts, -1)

      Enum.each(complete, fn event ->
        process_sse_event(event, acc, callback)
      end)

      %{acc | buffer: buffer}
    end)
  end

  defp process_sse_event(event, acc, callback) do
    event
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "data: "))
    |> Enum.map(&String.slice(&1, 6, String.length(&1)))
    |> Enum.join("")
    |> case do
      "" ->
        :ok

      "[DONE]" ->
        :ok

      json ->
        case Jason.decode(json) do
          {:ok, data} -> handle_stream_data(data, acc, callback)
          {:error, _} -> :ok
        end
    end
  end

  defp handle_stream_data(data, acc, callback) do
    choice = List.first(data["choices"] || [])
    delta = choice["delta"] || %{}

    acc =
      case delta["content"] do
        nil ->
          acc

        content ->
          callback.({:content_delta, content})
          %{acc | content: acc.content <> content}
      end

    acc =
      case delta["tool_calls"] do
        nil -> acc
        deltas -> accumulate_tool_call_deltas(deltas, acc, callback)
      end

    case choice["finish_reason"] do
      nil -> acc
      reason -> %{acc | finish_reason: reason}
    end
  end

  defp accumulate_tool_call_deltas(deltas, acc, callback) do
    Enum.reduce(deltas, acc, fn delta, acc ->
      index = delta["index"] || 0

      current =
        Map.get(acc.tool_calls, index, %{
          id: nil,
          type: "function",
          function: %{name: "", arguments: ""}
        })

      current =
        if delta["id"] do
          %{current | id: delta["id"]}
        else
          current
        end

      current =
        if delta["type"] do
          %{current | type: delta["type"]}
        else
          current
        end

      function = delta["function"] || %{}

      current =
        if function["name"] do
          put_in(current.function.name, current.function.name <> function["name"])
        else
          current
        end

      current =
        if function["arguments"] do
          put_in(
            current.function.arguments,
            current.function.arguments <> function["arguments"]
          )
        else
          current
        end

      if function["name"] do
        callback.({:tool_call_name, %{index: index, name: current.function.name}})
      end

      if function["arguments"] do
        callback.({:tool_call_arguments_delta, %{index: index, arguments: function["arguments"]}})
      end

      %{acc | tool_calls: Map.put(acc.tool_calls, index, current)}
    end)
  end

  defp build_stream_response(acc) do
    tool_calls =
      acc.tool_calls
      |> Enum.sort_by(fn {index, _} -> index end)
      |> Enum.map(fn {_index, tc} ->
        arguments =
          case Jason.decode(tc.function.arguments) do
            {:ok, args} -> args
            {:error, _} -> %{}
          end

        %ToolCall{
          id: tc.id,
          name: tc.function.name,
          arguments: arguments,
          parse_error: nil
        }
      end)

    %Schema.Response{
      content: if(acc.content == "", do: nil, else: acc.content),
      tool_calls: if(tool_calls == [], do: nil, else: tool_calls),
      finish_reason: acc.finish_reason,
      usage: nil
    }
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
