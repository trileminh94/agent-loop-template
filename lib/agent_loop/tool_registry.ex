defmodule AgentLoop.ToolRegistry do
  @moduledoc """
  Registry for tools available to the agent loop.

  Supports:
  - Registering tool modules
  - Aliasing tool names
  - Filtering by allow/deny lists
  - Executing tools and wrapping results
  """

  alias AgentLoop.ToolDefinition
  alias AgentLoop.ToolResult

  @type t :: %__MODULE__{
          tools: %{String.t() => module()},
          aliases: %{String.t() => String.t()}
        }

  defstruct tools: %{},
            aliases: %{}

  @doc "Create an empty registry."
  def new, do: %__MODULE__{}

  @doc "Register a tool module under its `name/0`."
  def register(%__MODULE__{} = registry, tool_module) when is_atom(tool_module) do
    name = tool_module.name()
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
  def execute(%__MODULE__{} = registry, tool_call_id, name, args)
      when is_binary(tool_call_id) and is_binary(name) and is_map(args) do
    case resolve(registry, name) do
      :error ->
        ToolResult.error(tool_call_id, name, "unknown tool: #{name}")

      {:ok, tool_module, canonical_name} ->
        try do
          case tool_module.execute(args) do
            {:ok, content} ->
              ToolResult.ok(tool_call_id, canonical_name, content)

            {:error, reason} ->
              ToolResult.error(tool_call_id, canonical_name, reason)
          end
        rescue
          error ->
            ToolResult.error(
              tool_call_id,
              canonical_name,
              "tool #{canonical_name} crashed: #{Exception.message(error)}"
            )
        catch
          kind, value ->
            ToolResult.error(
              tool_call_id,
              canonical_name,
              "tool #{canonical_name} threw: #{inspect({kind, value})}"
            )
        end
    end
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
