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
  alias AgentLoop.MCP.Client, as: MCPClient
  alias AgentLoop.MCP.Server, as: MCPServer
  alias AgentLoop.MCP.ToolBridge
  alias AgentLoop.Message
  alias AgentLoop.Provider.Schema
  alias AgentLoop.RunRequest
  alias AgentLoop.RunResult
  alias AgentLoop.ToolCall
  alias AgentLoop.ToolRegistry
  alias AgentLoop.ToolResult
  alias AgentLoop.Tools.Context
  alias AgentLoop.Tools.MCP, as: MCPTool

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

    {mcp_clients, config} = start_mcp(config)

    try do
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
    after
      stop_mcp(mcp_clients)
    end
  end

  # ---------------------------------------------------------------------------
  # MCP lifecycle
  # ---------------------------------------------------------------------------

  defp start_mcp(%LoopConfig{mcp_servers: []} = config) do
    {%{}, config}
  end

  defp start_mcp(%LoopConfig{} = config) do
    clients =
      Enum.reduce(config.mcp_servers, %{}, fn %MCPServer{} = server, acc ->
        case MCPClient.start(server) do
          {:ok, client} ->
            Map.put(acc, server.name, client)

          {:error, reason} ->
            IO.warn("failed to start MCP server #{server.name}: #{inspect(reason)}")
            acc
        end
      end)

    registry = build_mcp_registry(config.registry, clients)
    {clients, %{config | registry: registry, mcp_clients: clients}}
  end

  defp build_mcp_registry(registry, clients) do
    registry = ToolRegistry.register(registry, MCPTool)

    Enum.reduce(clients, registry, fn {server_name, client}, acc ->
      case MCPClient.list_tools(client) do
        {:ok, tools} ->
          Enum.reduce(tools, acc, fn tool, reg ->
            definition = ToolBridge.to_definition(server_name, tool)
            ToolRegistry.register_as(reg, definition.function.name, MCPTool)
          end)

        {:error, _reason} ->
          acc
      end
    end)
  end

  defp stop_mcp(clients) do
    Enum.each(clients, fn {_name, client} -> MCPClient.stop(client) end)
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

    request = %Schema.Request{
      model: config.model,
      messages: state.messages,
      tools: tool_defs,
      temperature: config.temperature,
      max_tokens: config.max_tokens
    }

    case call_provider_with_retries(config, request, config.max_retries) do
      {:ok, response} ->
        handle_response(state, config, response)

      {:error, reason} ->
        if context_length_error?(reason) and
             state.truncation_retries < config.max_truncation_retries and
             config.truncation_strategy != nil do
          emit(config, :truncation, %{reason: reason, strategy: config.truncation_strategy})

          state
          |> truncate_messages(config)
          |> then(&iterate(%{&1 | truncation_retries: state.truncation_retries + 1}, config))
        else
          finalize(%{state | finish_reason: :error}, config)
        end
    end
  end

  defp context_length_error?(%{
         status: 400,
         body: %{"error" => %{"code" => "context_length_exceeded"}}
       }),
       do: true

  defp context_length_error?(%{status: 400, body: %{"error" => %{"message" => message}}}) do
    is_binary(message) and String.contains?(message, "context length")
  end

  defp context_length_error?(%{status: 413}), do: true
  defp context_length_error?(_reason), do: false

  defp truncate_messages(state, %{truncation_strategy: :drop_oldest}) do
    messages = state.messages

    {prefix, truncatable} =
      case messages do
        [%Message{role: :system} | rest] -> {[hd(messages)], rest}
        _ -> {[], messages}
      end

    drop_count = max(div(length(truncatable), 2), 1)
    kept = Enum.drop(truncatable, drop_count)

    %{state | messages: prefix ++ kept}
  end

  defp truncate_messages(state, _config), do: state

  defp call_provider_with_retries(config, request, retries_remaining) do
    case call_provider(config, request) do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} = error ->
        if retries_remaining > 0 and retryable?(config, reason) do
          Process.sleep(config.retry_backoff_ms)
          call_provider_with_retries(config, request, retries_remaining - 1)
        else
          error
        end
    end
  end

  defp retryable?(%LoopConfig{retry_on: nil}, _reason), do: true
  defp retryable?(%LoopConfig{retry_on: fun}, reason) when is_function(fun, 1), do: fun.(reason)
  defp retryable?(_config, _reason), do: false

  defp call_provider(%LoopConfig{stream: true} = config, request) do
    provider = config.provider.__struct__

    if function_exported?(provider, :chat_stream, 3) do
      provider.chat_stream(config.provider, request, &emit_stream_delta(config, &1))
    else
      provider.chat(config.provider, request)
    end
  end

  defp call_provider(config, request) do
    config.provider.__struct__.chat(config.provider, request)
  end

  defp emit_stream_delta(config, {:content_delta, content}) do
    emit(config, :content_delta, %{content: content})
  end

  defp emit_stream_delta(config, {:tool_call_name, delta}) do
    emit(config, :tool_call_name, delta)
  end

  defp emit_stream_delta(config, {:tool_call_arguments_delta, delta}) do
    emit(config, :tool_call_arguments_delta, delta)
  end

  # ---------------------------------------------------------------------------
  # Response handling
  # ---------------------------------------------------------------------------

  defp handle_response(state, config, %Schema.Response{tool_calls: tool_calls} = response)
       when is_list(tool_calls) and length(tool_calls) > 0 do
    assistant_msg = Message.assistant(response.content, tool_calls: tool_calls)
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

  defp handle_response(state, _config, %Schema.Response{content: content} = response) do
    state = append_message(state, Message.assistant(content))

    finalize(
      %{
        state
        | final_content: content,
          final_thinking: response.thinking,
          usage: response.usage
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
    emit(config, :tool_call, %{
      id: tool_call.id,
      name: tool_call.name,
      arguments: tool_call.arguments
    })

    result = execute_approved_tool(config, tool_call)
    state = emit_tool_result(state, config, result)
    append_message(state, build_tool_message(result))
  end

  defp execute_tool_calls(state, config, tool_calls) do
    # Multiple tools: approve sequentially (so prompts don't interleave), then
    # execute the approved calls in parallel.
    emit(config, :tool_calls, %{count: length(tool_calls), names: Enum.map(tool_calls, & &1.name)})

    Enum.each(tool_calls, fn tc ->
      emit(config, :tool_call, %{id: tc.id, name: tc.name, arguments: tc.arguments})
    end)

    base_context = build_context(config)

    calls =
      Enum.map(tool_calls, fn tc ->
        case maybe_approve(config.approval, tc, base_context) do
          {:ok, context} -> {:run, tc, context}
          {:error, reason} -> {:error, ToolResult.error(tc.id, tc.name, reason)}
        end
      end)

    {to_run, _denied} = Enum.split_with(calls, &match?({:run, _, _}, &1))

    run_results =
      to_run
      |> Task.async_stream(
        fn {:run, tc, context} -> run_approved_tool(config, tc, context) end,
        ordered: true,
        max_concurrency: length(tool_calls),
        timeout: config.tool_timeout_ms
      )
      |> Enum.map(fn {:ok, result} -> result end)

    results = reconstruct_results(calls, run_results, [])

    Enum.reduce(results, state, fn result, acc ->
      acc = emit_tool_result(acc, config, result)
      append_message(acc, build_tool_message(result))
    end)
  end

  defp reconstruct_results([], [], acc), do: Enum.reverse(acc)

  defp reconstruct_results([{:run, _, _} | calls], [result | run_results], acc) do
    reconstruct_results(calls, run_results, [result | acc])
  end

  defp reconstruct_results([{:error, result} | calls], run_results, acc) do
    reconstruct_results(calls, run_results, [result | acc])
  end

  defp execute_approved_tool(config, tool_call) do
    case maybe_approve(config.approval, tool_call, build_context(config)) do
      {:ok, context} -> run_approved_tool(config, tool_call, context)
      {:error, reason} -> ToolResult.error(tool_call.id, tool_call.name, reason)
    end
  end

  defp run_approved_tool(config, %ToolCall{id: id, name: name, arguments: args}, context) do
    resolved_name = ToolRegistry.strip_prefix(name, config.tool_call_prefix)
    result = ToolRegistry.execute(config.registry, id, resolved_name, args, context)

    emit(config, :tool_result, %{
      id: id,
      name: result.name,
      content: truncate(result.content, 500),
      is_error: result.is_error,
      user_content: result.user_content,
      silent: result.silent
    })

    result
  end

  defp build_context(config) do
    %Context{
      session_id: config.session_id,
      persistence: config.persistence,
      mcp_clients: config.mcp_clients
    }
  end

  defp maybe_approve(nil, _tool_call, context), do: {:ok, context}

  defp maybe_approve(approval, tool_call, context) do
    if approval.requires_approval?(tool_call, context) do
      case approval.approve(tool_call, context) do
        :ok -> {:ok, %{context | approved: true}}
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, context}
    end
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
