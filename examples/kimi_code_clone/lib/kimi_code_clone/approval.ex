defmodule KimiCodeClone.Approval do
  @moduledoc """
  Interactive approval for destructive or powerful tools.
  """

  @approval_required ~w(
    shell_exec
    write_file
  )

  @doc "Return true if the named tool requires user approval."
  def requires_approval?(name) do
    # Strip MCP prefix if present.
    base = name |> String.split("__") |> List.last() |> Kernel.||(name)
    base in @approval_required
  end

  @doc "Prompt the user for approval. Returns true if approved."
  def prompt(tool_name, args) do
    IO.puts("\n--- Approval required ---")
    IO.puts("Tool: #{tool_name}")
    IO.puts("Arguments:")
    IO.puts(Jason.encode!(args, pretty: true))
    IO.write("Approve? (y/N) ")

    case IO.gets("") do
      :eof -> false
      input -> String.downcase(String.trim(input)) in ["y", "yes"]
    end
  end
end
