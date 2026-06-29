defmodule AgentLoop.Loop do
  @moduledoc """
  Core think → act → observe loop.

  This module is intentionally process-free. It takes a `RunRequest` and
  `LoopConfig`, iterates, and returns a `RunResult`. Consumers can wrap it
  in a GenServer or process if they need lifecycle management.
  """

  alias AgentLoop.Event
  alias AgentLoop.LoopConfig
  alias AgentLoop.LoopState
  alias AgentLoop.Message
  alias AgentLoop.RunRequest
  alias AgentLoop.RunResult
  alias AgentLoop.ToolCall
  alias AgentLoop.ToolRegistry
  alias AgentLoop.Tools.Context

  @doc "Run the agent loop."
  def run(%RunRequest{} = request, %LoopConfig{} = config) do
    {adapter, persistence_state} = config.persistence

    loaded_history =
      if request.session_id do
        case adapter.load_session(persistence_state, request.session_id) do
          {:ok, %{messages: messages}} -> messages
          _ -> []
        end
      else
        []
      end

    state = %LoopState{
      messages: build_initial_messages(request, config, loaded_history),
      iteration: 0,
      total_tool_calls: 0,
      pending_messages: [],
      final_content: nil,
      final_thinking: nil,
      usage: nil,
      truncation_retries: 0,
      finish_reason: :complete
    }

    config =
      %{config | session_id: request.session_id}
      |> then(fn config ->
        if config.trace or request.session_id do
          %{config | event_callback: wrap_callback(config, request)}
        else
          config
        end
      end)

    emit(config, :run_started, %{message: request.message})

    result = iterate(state, config)

    if request.session_id do
      adapter.save_session(
        persistence_state,
        request.session_id,
        result.messages,
        session_metadata(request, result)
      )
    end

    emit(config, :run_completed, %{
      content: result.content,
      iterations: result.iterations,
      total_tool_calls: result.total_tool_calls,
      finish_reason: result.finish_reason
    })

    result
  end

  # ---------------------------------------------------------------------------
  # Iteration
  # ---------------------------------------------------------------------------

  defp iterate(
         %LoopState{iteration: iteration} = state,
         %LoopConfig{max_iterations: max} = config
       )
       when iteration >= max do
    finalize(%{state | finish_reason: :max_iterations}, config)
  end

  defp iterate(%LoopState{} = state, %LoopConfig{} = config) do
    state = %{state | iteration: state.iteration + 1}

    emit(config, :thinking, %{iteration: state.iteration})

    tool_defs =
      ToolRegistry.definitions(config.registry,
        allow: config.allow_tools,
        deny: config.deny_tools
      )

    request = %{
      model: config.model,
      messages: state.messages,
      tools: tool_defs,
      temperature: config.temperature,
      max_tokens: config.max_tokens
    }

    case config.provider.__struct__.chat(config.provider, request) do
      {:ok, response} ->
        handle_response(state, config, response)

      {:error, _reason} ->
        finalize(%{state | finish_reason: :error}, config)
    end
  end

  # ---------------------------------------------------------------------------
  # Response handling
  # ---------------------------------------------------------------------------

  defp handle_response(state, config, %{tool_calls: tool_calls} = response)
       when is_list(tool_calls) and length(tool_calls) > 0 do
    assistant_msg = Message.assistant(Map.get(response, :content), tool_calls: tool_calls)
    state = append_message(state, assistant_msg)

    state = %{state | total_tool_calls: state.total_tool_calls + length(tool_calls)}

    if config.max_tool_calls > 0 and state.total_tool_calls > config.max_tool_calls do
      warning =
        Message.user(
          "[System] Tool call budget reached (#{state.total_tool_calls}/#{config.max_tool_calls}). " <>
            "Do NOT call any more tools. Summarize results so far and respond to the user."
        )

      iterate(%{state | messages: state.messages ++ [warning]}, config)
    else
      state = execute_tool_calls(state, config, tool_calls)
      iterate(state, config)
    end
  end

  defp handle_response(state, _config, %{content: content} = response) do
    state = append_message(state, Message.assistant(content))

    finalize(
      %{
        state
        | final_content: content,
          final_thinking: Map.get(response, :thinking),
          usage: Map.get(response, :usage)
      },
      nil
    )
  end

  defp handle_response(state, _config, _response) do
    finalize(%{state | finish_reason: :error}, nil)
  end

  # ---------------------------------------------------------------------------
  # Tool execution
  # ---------------------------------------------------------------------------

  defp execute_tool_calls(state, config, [tool_call]) do
    # Single tool: no Task overhead.
    result = execute_single_tool(config, tool_call)
    state = emit_tool_result(state, config, result)
    append_message(state, build_tool_message(result))
  end

  defp execute_tool_calls(state, config, tool_calls) do
    # Multiple tools: execute in parallel with bounded concurrency.
    emit(config, :tool_calls, %{count: length(tool_calls), names: Enum.map(tool_calls, & &1.name)})

    results =
      tool_calls
      |> Task.async_stream(
        fn tc -> execute_single_tool(config, tc) end,
        ordered: true,
        max_concurrency: length(tool_calls)
      )
      |> Enum.map(fn {:ok, result} -> result end)

    Enum.reduce(results, state, fn result, acc ->
      acc = emit_tool_result(acc, config, result)
      append_message(acc, build_tool_message(result))
    end)
  end

  defp execute_single_tool(config, %ToolCall{id: id, name: name, arguments: args}) do
    emit(config, :tool_call, %{id: id, name: name, arguments: args})

    resolved_name = ToolRegistry.strip_prefix(name, config.tool_call_prefix)

    Context.put(config.session_id, config.persistence)

    result = ToolRegistry.execute(config.registry, id, resolved_name, args)

    Context.clear()

    emit(config, :tool_result, %{
      id: id,
      name: result.name,
      content: truncate(result.content, 500),
      is_error: result.is_error
    })

    result
  end

  defp build_tool_message(%{tool_call_id: id, content: content, is_error: is_error}) do
    Message.tool(id, content, is_error: is_error)
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp build_initial_messages(%RunRequest{} = request, %LoopConfig{} = config, loaded_history) do
    messages =
      if config.system_prompt do
        [Message.system(config.system_prompt)]
      else
        []
      end

    messages = messages ++ loaded_history ++ request.history

    if request.message != nil and request.message != "" do
      messages ++ [Message.user(request.message)]
    else
      messages
    end
  end

  defp append_message(%LoopState{} = state, %Message{} = message) do
    %{
      state
      | messages: state.messages ++ [message],
        pending_messages: state.pending_messages ++ [message]
    }
  end

  defp emit_tool_result(%LoopState{} = state, _config, _result), do: state

  defp emit(%LoopConfig{event_callback: nil}, _type, _payload), do: :ok

  defp emit(%LoopConfig{event_callback: callback}, type, payload) when is_function(callback, 1) do
    callback.(Event.new(type, payload))
    :ok
  end

  defp finalize(%LoopState{} = state, _config) do
    %RunResult{
      content: state.final_content,
      thinking: state.final_thinking,
      messages: state.messages,
      iterations: state.iteration,
      total_tool_calls: state.total_tool_calls,
      usage: state.usage,
      finish_reason: state.finish_reason
    }
  end

  defp wrap_callback(config, request) do
    original = config.event_callback

    fn event ->
      if original, do: original.(event)

      {adapter, state} = config.persistence

      adapter.write_trace(
        state,
        request.session_id,
        request.run_id,
        %{type: event.type, payload: event.payload}
      )

      :ok
    end
  end

  defp session_metadata(request, result) do
    %{
      "run_id" => request.run_id,
      "finish_reason" => result.finish_reason,
      "iterations" => result.iterations,
      "total_tool_calls" => result.total_tool_calls
    }
  end

  defp truncate(nil, _max), do: ""

  defp truncate(str, max) when is_binary(str) and byte_size(str) > max,
    do: String.slice(str, 0, max) <> "..."

  defp truncate(str, _max), do: to_string(str)
end
