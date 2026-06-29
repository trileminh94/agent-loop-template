defmodule AgentLoop.Tools.Workspace do
  @moduledoc """
  Workspace resolution and path safety helpers for coding tools.

  Inspired by goclaw's workspace restriction model, but kept minimal:
  tools resolve relative paths against a configured workspace root and can
  optionally be restricted to that root.
  """

  @app :agent_loop

  @doc """
  Set the workspace root and restriction flag.

  ## Options

    * `:root` - directory to resolve relative paths against (default: `File.cwd!()`)
    * `:restrict` - when `true`, reject paths that resolve outside the root
  """
  def configure(opts \\ []) do
    root = Keyword.get(opts, :root, File.cwd!())
    restrict = Keyword.get(opts, :restrict, true)

    Application.put_env(@app, __MODULE__, %{
      root: Path.expand(root),
      restrict: restrict
    })

    :ok
  end

  @doc "Reset workspace configuration to defaults."
  def reset do
    Application.delete_env(@app, __MODULE__)
  end

  @doc "Return the configured workspace root."
  def root do
    config = Application.get_env(@app, __MODULE__, %{})
    Map.get(config, :root, File.cwd!())
  end

  @doc "Return true if paths must stay inside the workspace root."
  def restrict? do
    config = Application.get_env(@app, __MODULE__, %{})
    Map.get(config, :restrict, true)
  end

  @doc """
  Resolve a path relative to the workspace root.

  Absolute paths are used as-is. Relative paths are joined to the root.
  When restriction is enabled, the resolved path must be inside the root.
  """
  def resolve(path) when is_binary(path) do
    root = root()

    resolved =
      if Path.type(path) == :absolute do
        Path.expand(path)
      else
        Path.expand(path, root)
      end

    if restrict?() and not within?(resolved, root) do
      {:error, "path '#{path}' resolves outside workspace: #{root}"}
    else
      {:ok, resolved}
    end
  end

  @doc """
  Return a user-facing relative path when the file is inside the workspace,
  otherwise return the absolute path.
  """
  def display_path(absolute_path) do
    root = root()

    if within?(absolute_path, root) do
      Path.relative_to(absolute_path, root)
    else
      absolute_path
    end
  end

  defp within?(path, root) do
    String.starts_with?(path, root)
  end
end
