defmodule Mix.Tasks.Kimi.Run do
  @moduledoc """
  Run the Kimi Code Clone agent.

  ## Usage

      mix kimi.run "find all TODOs" --session feature-x
      mix kimi.run "explain the project" --workspace ./my_project

  ## Options

      --workspace PATH    Target workspace (default: current directory)
      --session ID        Session id for persistence (default: default)
      --model MODEL       LLM model (default: gpt-4o-mini)
      --base-url URL      Provider base URL

  ## Environment

      OPENAI_API_KEY      Required

  """

  use Mix.Task

  alias KimiCodeClone.Session

  @impl true
  def run(args) do
    {opts, [prompt], _errors} =
      OptionParser.parse(args,
        strict: [
          workspace: :string,
          session: :string,
          model: :string,
          base_url: :string
        ],
        aliases: [w: :workspace, s: :session, m: :model]
      )

    workspace = Keyword.get(opts, :workspace, File.cwd!())
    session_id = Keyword.get(opts, :session, "default")
    model = Keyword.get(opts, :model, Application.get_env(:kimi_code_clone, :model))
    base_url = Keyword.get(opts, :base_url, System.get_env("BASE_URL", "https://api.openai.com/v1"))
    api_key = System.get_env("OPENAI_API_KEY")

    if is_nil(api_key) or api_key == "" do
      Mix.raise("OPENAI_API_KEY is not set")
    end

    Application.ensure_all_started(:agent_loop)
    Application.ensure_all_started(:kimi_code_clone)

    Session.start_link(
      workspace: workspace,
      model: model,
      base_url: base_url,
      api_key: api_key
    )

    result = Session.run(prompt, session_id)

    IO.puts("\n---")
    IO.puts("Finished in #{result.iterations} iteration(s), #{result.total_tool_calls} tool call(s)")
    IO.puts("Reason: #{result.finish_reason}")
    IO.puts("\n#{result.content}")
  end
end
