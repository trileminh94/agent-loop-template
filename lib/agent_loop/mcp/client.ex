defmodule AgentLoop.MCP.Client do
  @moduledoc """
  Stdio MCP client.

  Starts an external MCP server as a Port, sends JSON-RPC requests, and
  returns responses. The client is intentionally synchronous: each call waits
  for the matching response (ignoring notifications and log lines).

  ## Example

      {:ok, client} = AgentLoop.MCP.Client.start(server)
      :ok = AgentLoop.MCP.Client.initialize(client)
      {:ok, tools} = AgentLoop.MCP.Client.list_tools(client)
      {:ok, result} = AgentLoop.MCP.Client.call_tool(client, "read_file", %{"path" => "README.md"})
      :ok = AgentLoop.MCP.Client.stop(client)

  """

  alias AgentLoop.MCP.Messages
  alias AgentLoop.MCP.Server

  defstruct port: nil,
            server: nil,
            next_id: 1

  @type t :: %__MODULE__{
          port: port(),
          server: Server.t(),
          next_id: pos_integer()
        }

  @doc "Start the MCP server and return a client."
  def start(%Server{} = server) do
    opts = [:binary, :line, :exit_status, args: List.wrap(server.args)]

    env =
      Enum.map(server.env, fn {k, v} ->
        {String.to_charlist(k), String.to_charlist(v)}
      end)

    opts = if env == [], do: opts, else: [{:env, env} | opts]

    port = Port.open({:spawn_executable, System.find_executable(server.command)}, opts)

    client = %__MODULE__{port: port, server: server, next_id: 1}

    with :ok <- initialize(client) do
      {:ok, client}
    else
      {:error, reason} ->
        stop(client)
        {:error, reason}
    end
  end

  @doc "Send the initialize handshake."
  def initialize(%__MODULE__{} = client) do
    {client, id} = next_id(client)

    with :ok <- send_message(client, Messages.initialize(id)),
         {:ok, %{"result" => _}} <- recv_response(client, id),
         :ok <- send_message(client, Messages.initialized_notification()) do
      :ok
    end
  end

  @doc "List tools exposed by the server."
  def list_tools(%__MODULE__{} = client) do
    {client, id} = next_id(client)

    with :ok <- send_message(client, Messages.tools_list(id)),
         {:ok, %{"result" => %{"tools" => tools}}} <- recv_response(client, id) do
      {:ok, tools}
    end
  end

  @doc "Call an MCP tool by name."
  def call_tool(%__MODULE__{} = client, name, args) when is_binary(name) and is_map(args) do
    {client, id} = next_id(client)

    with :ok <- send_message(client, Messages.tools_call(id, name, args)),
         {:ok, %{"result" => result}} <- recv_response(client, id) do
      {:ok, result}
    end
  end

  @doc "Stop the client and terminate the server process."
  def stop(%__MODULE__{port: port}) do
    if port do
      Port.close(port)
    end

    :ok
  end

  # ---------------------------------------------------------------------------
  # Internals
  # ---------------------------------------------------------------------------

  defp next_id(%__MODULE__{next_id: id} = client) do
    {%{client | next_id: id + 1}, id}
  end

  defp send_message(%__MODULE__{port: port}, message) do
    Port.command(port, message)
    :ok
  end

  defp recv_response(client, id, timeout \\ 30_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    recv_until(client, id, deadline)
  end

  defp recv_until(%__MODULE__{port: port} = client, id, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      {:error, :timeout}
    else
      timeout = min(remaining, 5_000)

      receive do
        {^port, {:data, data}} ->
          case parse_line(data) do
            {:ok, %{"id" => ^id} = response} ->
              handle_response(response)

            {:ok, %{"method" => _}} ->
              # Notification; keep waiting.
              recv_until(client, id, deadline)

            {:ok, %{"id" => _other_id}} ->
              # Response to a different request; ignore.
              recv_until(client, id, deadline)

            :error ->
              recv_until(client, id, deadline)
          end

        {^port, {:exit_status, 0}} ->
          {:error, :server_exit}

        {^port, {:exit_status, code}} ->
          {:error, {:server_exit, code}}
      after
        timeout ->
          recv_until(client, id, deadline)
      end
    end
  end

  defp parse_line({:eol, line}), do: parse_line(line)

  defp parse_line(line) do
    case Jason.decode(line) do
      {:ok, json} when is_map(json) -> {:ok, json}
      _ -> :error
    end
  end

  defp handle_response(%{"error" => error}) when is_map(error) do
    {:error, "#{Map.get(error, "code")}: #{Map.get(error, "message")}"}
  end

  defp handle_response(%{"result" => _} = response) do
    {:ok, response}
  end

  defp handle_response(_response) do
    {:error, :invalid_response}
  end
end
