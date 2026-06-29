defmodule Mix.Tasks.Agent.Run do
  @moduledoc """
  Run the agent loop from the command line.

  ## Usage

      mix agent.run "read README.md and summarize it"

  ## Options

      --provider NAME     LLM provider: openai or deepseek (default: openai)
      --workspace PATH    Workspace directory (default: current directory)
      --model MODEL       LLM model (provider defaults apply)
      --base-url URL      Provider base URL (provider defaults apply)
      --session ID        Session id for resuming conversations
      --memory-db PATH    SQLite database file for persistence (default: .agent_loop/sessions.db)
      --trace             Persist execution traces
      --no-restrict       Allow paths outside the workspace
      --max-iterations N  Maximum loop iterations (default: 10)

  ## Environment

      OPENAI_API_KEY      Required when --provider openai
      DEEPSEEK_API_KEY    Required when --provider deepseek

  """

  use Mix.Task

  alias AgentLoop.Persistence
  alias AgentLoop.ToolRegistry
  alias AgentLoop.Tools.EditFile
  alias AgentLoop.Tools.FetchURL
  alias AgentLoop.Tools.Grep
  alias AgentLoop.Tools.ListFiles
  alias AgentLoop.Tools.Memory
  alias AgentLoop.Tools.ReadFile
  alias AgentLoop.Tools.ShellExec
  alias AgentLoop.Tools.WriteFile
  alias AgentLoop.Tools.Workspace

  @impl true
  def run(args) do
    Application.ensure_all_started(:agent_loop)

    {opts, [prompt], _errors} =
      OptionParser.parse(args,
        strict: [
          provider: :string,
          workspace: :string,
          model: :string,
          base_url: :string,
          session: :string,
          memory_db: :string,
          trace: :boolean,
          restrict: :boolean,
          max_iterations: :integer
        ],
        aliases: [p: :provider, w: :workspace, m: :model]
      )

    provider_name = Keyword.get(opts, :provider, "openai")
    provider_config = Map.fetch!(providers(), provider_name)

    workspace = Keyword.get(opts, :workspace, File.cwd!())
    restrict = Keyword.get(opts, :restrict, true)
    model = Keyword.get(opts, :model, provider_config.default_model)
    base_url = Keyword.get(opts, :base_url, provider_config.default_base_url)
    session_id = Keyword.get(opts, :session)
    memory_db = Keyword.get(opts, :memory_db, Path.join(workspace, ".agent_loop/sessions.db"))
    trace? = Keyword.get(opts, :trace, false)
    max_iterations = Keyword.get(opts, :max_iterations, 10)

    Workspace.configure(root: workspace, restrict: restrict)

    api_key = System.get_env(provider_config.env)

    if is_nil(api_key) or api_key == "" do
      Mix.raise("#{provider_config.env} is not set")
    end

    provider = provider_config.builder.(api_key, base_url)

    persistence =
      if not is_nil(session_id) or trace? do
        {:ok, persistence} = Persistence.new(AgentLoop.Persistence.SQLite, database: memory_db)
        persistence
      else
        {AgentLoop.Persistence.NoOp, nil}
      end

    registry =
      ToolRegistry.new()
      |> ToolRegistry.register_many([
        ReadFile,
        ListFiles,
        WriteFile,
        EditFile,
        Grep,
        ShellExec,
        FetchURL,
        Memory
      ])

    system_prompt =
      """
      You are a helpful coding assistant operating inside the workspace:
      #{Path.expand(workspace)}

      You have access to file, search, shell, web, and memory tools.
      Think step by step. Use tools when needed. Prefer small, precise edits.
      """

    config =
      AgentLoop.LoopConfig.new(provider, registry,
        model: model,
        system_prompt: system_prompt,
        max_iterations: max_iterations,
        persistence: persistence,
        trace: trace?,
        event_callback: &handle_event/1
      )

    request = AgentLoop.RunRequest.new(prompt, session_id: session_id)
    result = AgentLoop.run(request, config)

    IO.puts("\n---")

    IO.puts(
      "Finished in #{result.iterations} iteration(s), #{result.total_tool_calls} tool call(s)"
    )

    IO.puts("Reason: #{result.finish_reason}")
    IO.puts("Session: #{session_id || "(none)"}")
    IO.puts("\n#{result.content}")

    Workspace.reset()
  end

  defp providers do
    %{
      "openai" => %{
        env: "OPENAI_API_KEY",
        default_model: "gpt-4o-mini",
        default_base_url: "https://api.openai.com/v1",
        builder: fn api_key, base_url ->
          %AgentLoop.Provider.OpenAICompatible{
            api_key: api_key,
            base_url: base_url,
            http_options: [receive_timeout: 120_000]
          }
        end
      },
      "deepseek" => %{
        env: "DEEPSEEK_API_KEY",
        default_model: "deepseek-chat",
        default_base_url: "https://api.deepseek.com",
        builder: fn api_key, base_url ->
          %AgentLoop.Provider.DeepSeek{
            api_key: api_key,
            base_url: base_url,
            http_options: [receive_timeout: 120_000]
          }
        end
      }
    }
  end

  defp handle_event(%{type: :thinking, payload: %{iteration: n}}) do
    IO.puts("[thinking: iteration #{n}]")
  end

  defp handle_event(%{type: :tool_call, payload: %{name: name}}) do
    IO.puts("[tool call: #{name}]")
  end

  defp handle_event(%{
         type: :tool_result,
         payload: %{name: name, is_error: true, content: content}
       }) do
    IO.puts("[tool error: #{name}] #{String.trim(content)}")
  end

  defp handle_event(%{type: :tool_result, payload: %{name: name, content: content}}) do
    IO.puts("[tool result: #{name}] #{String.trim(content)}")
  end

  defp handle_event(_event) do
    :ok
  end
end
