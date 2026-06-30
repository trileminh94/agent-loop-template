defmodule KimiCodeClone.Session do
  @moduledoc """
  Supervised session that wraps the agent loop.

  Holds the `LoopConfig` (provider, registry, persistence) and runs prompts
  on demand. Events are streamed to a callback so the CLI can print progress.
  """

  use GenServer

  alias AgentLoop.Approval.Terminal, as: TerminalApproval
  alias AgentLoop.LoopConfig
  alias AgentLoop.Persistence
  alias AgentLoop.Tools.Workspace

  alias KimiCodeClone.Prompts
  alias KimiCodeClone.Tools.Registry, as: ToolRegistryBuilder

  defstruct config: nil, workspace: nil

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    workspace = Keyword.get(opts, :workspace, File.cwd!())
    model = Keyword.get(opts, :model, "gpt-4o-mini")
    base_url = Keyword.get(opts, :base_url, "https://api.openai.com/v1")
    api_key = Keyword.get(opts, :api_key)

    if is_nil(api_key) or api_key == "" do
      raise "OPENAI_API_KEY is not set"
    end

    Workspace.configure(root: workspace, restrict: true)

    provider = %AgentLoop.Provider.OpenAICompatible{
      api_key: api_key,
      base_url: base_url,
      http_options: [receive_timeout: 120_000]
    }

    registry = ToolRegistryBuilder.build()

    {:ok, persistence} =
      Persistence.new(AgentLoop.Persistence.SQLite,
        database: Path.join(workspace, ".kimi_code_clone/sessions.db")
      )

    config =
      LoopConfig.new(provider, registry,
        model: model,
        system_prompt: Prompts.coding_assistant(workspace),
        persistence: persistence,
        trace: true,
        max_iterations: 20,
        approval: TerminalApproval,
        event_callback: &handle_event/1
      )

    {:ok, %__MODULE__{config: config, workspace: workspace}}
  end

  @doc "Run a prompt in the given session. Blocks until the loop finishes."
  def run(prompt, session_id \\ "default") when is_binary(prompt) do
    GenServer.call(__MODULE__, {:run, prompt, session_id}, :infinity)
  end

  @doc "List persisted sessions."
  def list_sessions do
    GenServer.call(__MODULE__, :list_sessions)
  end

  @impl true
  def handle_call({:run, prompt, session_id}, _from, %{config: config} = state) do
    request = AgentLoop.RunRequest.new(prompt, session_id: session_id)
    result = AgentLoop.run(request, config)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:list_sessions, _from, %{config: config} = state) do
    {adapter, persistence_state} = config.persistence
    {:ok, sessions} = adapter.list_sessions(persistence_state, [])
    {:reply, sessions, state}
  end

  defp handle_event(%{type: :thinking, payload: %{iteration: n}}) do
    IO.puts("[thinking: iteration #{n}]")
  end

  defp handle_event(%{type: :tool_call, payload: %{name: name}}) do
    IO.puts("[tool: #{name}]")
  end

  defp handle_event(%{type: :tool_result, payload: %{name: name, is_error: true, content: content}}) do
    IO.puts("[tool error: #{name}] #{String.trim(content)}")
  end

  defp handle_event(%{type: :tool_result, payload: %{name: name, content: content}}) do
    IO.puts("[tool result: #{name}] #{String.trim(content)}")
  end

  defp handle_event(_event) do
    :ok
  end
end
