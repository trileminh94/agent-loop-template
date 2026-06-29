defmodule AgentLoop.MCP.Server do
  @moduledoc """
  Configuration for an MCP server.

  ## Example

      %AgentLoop.MCP.Server{
        name: "filesystem",
        command: "npx",
        args: ["-y", "@modelcontextprotocol/server-filesystem", "."],
        env: %{},
        timeout: 30_000
      }

  """

  @type t :: %__MODULE__{
          name: String.t(),
          command: String.t(),
          args: [String.t()],
          env: %{String.t() => String.t()},
          timeout: non_neg_integer()
        }

  defstruct name: nil,
            command: nil,
            args: [],
            env: %{},
            timeout: 30_000
end
