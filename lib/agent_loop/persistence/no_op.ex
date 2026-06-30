defmodule AgentLoop.Persistence.NoOp do
  @moduledoc """
  Default persistence adapter that does nothing.

  This keeps the template working without any persistence configuration.
  """

  @behaviour AgentLoop.Persistence

  alias AgentLoop.Message
  alias AgentLoop.ToolCall

  @impl true
  def init(_opts), do: {:ok, nil}

  @impl true
  def save_session(_state, _session_id, _messages, _metadata), do: :ok

  @impl true
  def load_session(_state, _session_id), do: {:ok, %{messages: [], metadata: %{}}}

  @impl true
  def list_sessions(_state, _opts), do: {:ok, []}

  @impl true
  def remember(_state, _session_id, _note), do: :ok

  @impl true
  def recall(_state, _session_id, _opts), do: {:ok, ""}

  @impl true
  def write_trace(_state, _session_id, _run_id, _event), do: :ok

  @impl true
  def get_trace(_state, _session_id, _run_id), do: {:ok, []}

  @doc "Serialize messages into a portable format for storage."
  def serialize_messages(messages) do
    Enum.map(messages, fn %Message{} = msg ->
      %{
        "role" => to_string(msg.role),
        "content" => msg.content,
        "tool_calls" => msg.tool_calls,
        "tool_call_id" => msg.tool_call_id,
        "name" => msg.name
      }
    end)
  end

  @doc "Deserialize stored messages back into Message structs."
  def deserialize_messages(list) when is_list(list) do
    Enum.map(list, fn map ->
      %Message{
        role: String.to_existing_atom(map["role"]),
        content: map["content"],
        tool_calls: decode_tool_calls(map["tool_calls"]),
        tool_call_id: map["tool_call_id"],
        name: map["name"]
      }
    end)
  end

  defp decode_tool_calls(nil), do: nil

  defp decode_tool_calls(list) when is_list(list) do
    Enum.map(list, fn
      %ToolCall{} = tc ->
        tc

      map ->
        %ToolCall{
          id: map["id"],
          name: map["name"],
          arguments: map["arguments"],
          parse_error: map["parse_error"]
        }
    end)
  end
end
