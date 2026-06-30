defmodule AgentLoop.ToolRegistry do
  @moduledoc """
  Registry for tools available to the agent loop.

  Supports:
  - Registering tool modules
  - Aliasing tool names
  - Filtering by allow/deny lists
  - Executing tools and wrapping results
  """

  alias AgentLoop.ToolCall
  alias AgentLoop.ToolDefinition
  alias AgentLoop.ToolResult

  @type t :: %__MODULE__{
          tools: %{String.t() => module()},
          aliases: %{String.t() => String.t()},
          middleware: [module()]
        }

  defstruct tools: %{},
            aliases: %{},
            middleware: []

  @doc "Create an empty registry."
  def new, do: %__MODULE__{}

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

  @doc "Register a middleware module."
  def add_middleware(%__MODULE__{} = registry, middleware_module)
      when is_atom(middleware_module) do
    %{registry | middleware: registry.middleware ++ [middleware_module]}
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

  @doc "Resolve a name to its canonical tool module, if any."
  def resolve(%__MODULE__{} = registry, name) when is_binary(name) do
    canonical = Map.get(registry.aliases, name, name)

    case Map.get(registry.tools, canonical) do
      nil -> :error
      tool_module -> {:ok, tool_module, canonical}
    end
  end

  @doc "Return all tool definitions, optionally filtered by allow/deny lists."
  def definitions(%__MODULE__{} = registry, opts \\ []) do
    allow = Keyword.get(opts, :allow)
    deny = Keyword.get(opts, :deny) || []

    registry.tools
    |> Map.keys()
    |> maybe_filter(allow, & &1)
    |> Enum.reject(fn name -> name in deny end)
    |> Enum.sort()
    |> Enum.map(fn name -> ToolDefinition.from_module(registry.tools[name]) end)
  end

  @doc "Execute a tool by name with the given arguments."
  def execute(%__MODULE__{} = registry, tool_call_id, name, args, context \\ nil)
      when is_binary(tool_call_id) and is_binary(name) and is_map(args) do
    case resolve(registry, name) do
      :error ->
        ToolResult.error(tool_call_id, name, "unknown tool: #{name}")

      {:ok, tool_module, canonical_name} ->
        tool_call = %ToolCall{id: tool_call_id, name: canonical_name, arguments: args}

        case run_before_middleware(registry.middleware, tool_call, context) do
          {:error, reason} ->
            ToolResult.error(tool_call_id, canonical_name, reason)

          {:ok, %ToolCall{} = prepared_call} ->
            result = execute_tool(tool_module, prepared_call, context)
            run_after_middleware(registry.middleware, result, prepared_call, context)
        end
    end
  end

  defp execute_tool(tool_module, %ToolCall{} = tool_call, context) do
    try do
      result = run_tool(tool_module, tool_call.name, tool_call.arguments, context)

      case result do
        {:ok, content} ->
          ToolResult.ok(tool_call.id, tool_call.name, content)

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

  defp run_before_middleware(middleware, tool_call, context) do
    Enum.reduce_while(middleware, {:ok, tool_call}, fn module, {:ok, call} ->
      case module.before_execute(call, context) do
        {:ok, %ToolCall{} = next_call} -> {:cont, {:ok, next_call}}
        {:error, reason} -> {:halt, {:error, reason}}
        other -> {:halt, {:error, "middleware #{module} returned invalid: #{inspect(other)}"}}
      end
    end)
  end

  defp run_after_middleware(middleware, result, tool_call, context) do
    Enum.reduce(middleware, result, fn module, acc ->
      module.after_execute(acc, tool_call, context)
    end)
  end

  defp run_tool(AgentLoop.Tools.MCP, canonical_name, args, context) do
    AgentLoop.Tools.MCP.execute_prefixed(canonical_name, args, context)
  end

  defp run_tool(tool_module, _canonical_name, args, _context) do
    tool_module.execute(args)
  end

  @doc "Strip a configured prefix from a tool-call name returned by the model."
  def strip_prefix(name, nil), do: name
  def strip_prefix(name, ""), do: name

  def strip_prefix(name, prefix) when is_binary(prefix) do
    if String.starts_with?(name, prefix) do
      String.replace_prefix(name, prefix, "")
    else
      name
    end
  end

  defp maybe_filter(names, nil, _key_fn), do: names

  defp maybe_filter(names, allow, key_fn),
    do: Enum.filter(names, fn name -> key_fn.(name) in allow end)
end
