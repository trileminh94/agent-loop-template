defmodule AgentLoop.ToolRegistry do
  @moduledoc """
  Registry of tool modules and their LLM-facing definitions.

  Supports:

    * aliases (e.g. `ls` → `list_files`)
    * enabled/disabled tools
    * deterministic, sorted tool definitions for provider APIs
    * context-aware execution with panic recovery

  Inspired by goclaw's tool registry, but kept minimal.
  """

  alias AgentLoop.ToolCall
  alias AgentLoop.ToolDefinition
  alias AgentLoop.ToolResult
  alias AgentLoop.Tools.Context
  alias AgentLoop.Tools.MCP, as: MCPTool

  @type t :: %__MODULE__{
          tools: %{String.t() => module()},
          aliases: %{String.t() => String.t()},
          disabled: MapSet.t(String.t()),
          middlewares: [module()]
        }

  defstruct tools: %{},
            aliases: %{},
            disabled: MapSet.new(),
            middlewares: []

  @doc "Create an empty registry."
  def new do
    %__MODULE__{}
  end

  @doc "Register a tool module under its `name/0`."
  def register(%__MODULE__{} = registry, tool_module) when is_atom(tool_module) do
    register_as(registry, tool_module.name(), tool_module)
  end

  @doc "Register a tool module under a custom name."
  def register_as(%__MODULE__{} = registry, name, tool_module)
      when is_binary(name) and is_atom(tool_module) do
    %{registry | tools: Map.put(registry.tools, name, tool_module)}
  end

  @doc "Register multiple tool modules."
  def register_many(%__MODULE__{} = registry, tool_modules) when is_list(tool_modules) do
    Enum.reduce(tool_modules, registry, &register(&2, &1))
  end

  @doc "Create an alias from one name to another canonical name."
  def register_alias(%__MODULE__{} = registry, alias_name, canonical_name)
      when is_binary(alias_name) and is_binary(canonical_name) do
    if Map.has_key?(registry.tools, alias_name) do
      registry
    else
      %{registry | aliases: Map.put(registry.aliases, alias_name, canonical_name)}
    end
  end

  @doc "Disable a tool (and its aliases) by name. Disabled tools are excluded from definitions and execution."
  def disable(%__MODULE__{} = registry, name) when is_binary(name) do
    %{registry | disabled: MapSet.put(registry.disabled, name)}
  end

  @doc "Re-enable a previously disabled tool."
  def enable(%__MODULE__{} = registry, name) when is_binary(name) do
    %{registry | disabled: MapSet.delete(registry.disabled, name)}
  end

  @doc "Add a middleware module to the registry."
  def add_middleware(%__MODULE__{} = registry, middleware_module)
      when is_atom(middleware_module) do
    %{registry | middlewares: registry.middlewares ++ [middleware_module]}
  end

  @doc "Return true if the tool is disabled."
  def disabled?(%__MODULE__{} = registry, name) when is_binary(name) do
    MapSet.member?(registry.disabled, name)
  end

  @doc "Resolve a name to its canonical name and tool module."
  def resolve(%__MODULE__{} = registry, name) when is_binary(name) do
    cond do
      Map.has_key?(registry.tools, name) and not disabled?(registry, name) ->
        {:ok, Map.fetch!(registry.tools, name), name}

      Map.has_key?(registry.aliases, name) ->
        canonical = Map.fetch!(registry.aliases, name)

        if disabled?(registry, canonical) do
          :error
        else
          case Map.fetch(registry.tools, canonical) do
            {:ok, module} -> {:ok, module, canonical}
            :error -> :error
          end
        end

      true ->
        :error
    end
  end

  @doc "Return LLM-facing definitions, sorted deterministically."
  def definitions(%__MODULE__{} = registry, opts \\ []) do
    allow = Keyword.get(opts, :allow)
    deny = Keyword.get(opts, :deny)
    prefix = Keyword.get(opts, :prefix)

    registry.tools
    |> Enum.reject(fn {name, _} -> disabled?(registry, name) end)
    |> Enum.filter(fn {name, _} ->
      allowed = is_nil(allow) or name in allow
      not_denied = is_nil(deny) or name not in deny
      allowed and not_denied
    end)
    |> Enum.map(fn {name, module} ->
      def_name = if prefix, do: "#{prefix}#{name}", else: name

      ToolDefinition.new(module,
        name: def_name,
        description: module.description(),
        parameters: module.parameters()
      )
    end)
    |> Enum.sort_by(& &1.function.name)
  end

  @doc """
  Execute a tool by name with the given arguments and context.

  The context is passed as the second argument to the tool's `execute/2` callback.
  Execution is wrapped in `try/catch` so a crashing tool returns an error result
  instead of bringing down the loop.

  Registered middleware is run before and after the tool call.
  """
  def execute(%__MODULE__{} = registry, tool_call_id, name, args, context \\ %Context{})
      when is_binary(tool_call_id) and is_binary(name) and is_map(args) do
    case resolve(registry, name) do
      :error ->
        ToolResult.error(tool_call_id, name, "unknown tool: #{name}")

      {:ok, tool_module, canonical_name} ->
        tool_call = %ToolCall{id: tool_call_id, name: canonical_name, arguments: args}

        case run_before_middlewares(registry.middlewares, tool_call, context) do
          {:ok, tool_call} ->
            result = execute_tool(tool_module, tool_call, context)
            run_after_middlewares(registry.middlewares, result, tool_call, context)

          {:error, reason} ->
            ToolResult.error(tool_call_id, canonical_name, reason)
        end
    end
  end

  defp execute_tool(MCPTool, %ToolCall{} = tool_call, context) do
    case MCPTool.execute_prefixed(tool_call.name, tool_call.arguments, context) do
      {:ok, content} ->
        ToolResult.ok(tool_call.id, tool_call.name, content)

      {:ok, content, user_content} ->
        ToolResult.ok(tool_call.id, tool_call.name, content, user_content)

      {:error, reason} ->
        ToolResult.error(tool_call.id, tool_call.name, reason)
    end
  end

  defp execute_tool(tool_module, %ToolCall{} = tool_call, context) do
    try do
      case tool_module.execute(tool_call.arguments, context) do
        {:ok, content} ->
          ToolResult.ok(tool_call.id, tool_call.name, content)

        {:ok, content, user_content} ->
          ToolResult.ok(tool_call.id, tool_call.name, content, user_content)

        {:error, reason} ->
          ToolResult.error(tool_call.id, tool_call.name, reason)
      end
    rescue
      error ->
        ToolResult.error(
          tool_call.id,
          tool_call.name,
          "tool #{tool_call.name} crashed: #{Exception.message(error)}"
        )
    catch
      kind, value ->
        ToolResult.error(
          tool_call.id,
          tool_call.name,
          "tool #{tool_call.name} threw: #{inspect({kind, value})}"
        )
    end
  end

  defp run_before_middlewares(middlewares, tool_call, context) do
    Enum.reduce_while(middlewares, {:ok, tool_call}, fn middleware, {:ok, acc} ->
      case middleware.before_execute(acc, context) do
        {:ok, new_call} -> {:cont, {:ok, new_call}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp run_after_middlewares(middlewares, result, tool_call, context) do
    middlewares
    |> Enum.reverse()
    |> Enum.reduce(result, fn middleware, acc ->
      middleware.after_execute(acc, tool_call, context)
    end)
  end

  @doc "Strip a prefix from a tool name, if present."
  def strip_prefix(name, nil), do: name

  def strip_prefix(name, prefix) when is_binary(prefix) do
    if String.starts_with?(name, prefix) do
      String.replace_prefix(name, prefix, "")
    else
      name
    end
  end
end
