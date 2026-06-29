defmodule AgentLoop.Persistence.SQLite do
  @moduledoc """
  SQLite-backed persistence adapter.

  Stores sessions, messages, memories, and traces in a local SQLite file.
  Migrations run automatically on `init/1`.

  ## Options

    * `:database` - path to the SQLite file (default: `".agent_loop/sessions.db"`)

  ## Usage

      {:ok, persistence} = AgentLoop.Persistence.new(AgentLoop.Persistence.SQLite, database: "data.db")

  """

  @behaviour AgentLoop.Persistence

  alias AgentLoop.Message
  alias AgentLoop.Persistence.Migrations.Initial
  alias Exqlite.Basic, as: Sqlite

  @default_database ".agent_loop/sessions.db"

  @impl true
  def init(opts \\ []) do
    database = Keyword.get(opts, :database, @default_database)

    with :ok <- File.mkdir_p(Path.dirname(database)),
         {:ok, conn} <- Sqlite.open(database),
         :ok <- migrate(conn),
         :ok <- Sqlite.close(conn) do
      {:ok, %{database: database}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def save_session(%{database: database}, session_id, messages, metadata) do
    now = now_iso()
    metadata_json = Jason.encode!(metadata)

    transaction(database, fn conn ->
      title = Map.get(metadata, "title", "Session #{String.slice(session_id, 0, 8)}")

      exec!(conn, "DELETE FROM messages WHERE session_id = ?", [session_id])

      exec!(
        conn,
        "INSERT INTO sessions (id, title, metadata, created_at, updated_at) VALUES (?, ?, ?, ?, ?) " <>
          "ON CONFLICT(id) DO UPDATE SET title = excluded.title, metadata = excluded.metadata, updated_at = excluded.updated_at",
        [session_id, title, metadata_json, now, now]
      )

      Enum.each(messages, fn %Message{} = msg ->
        exec!(
          conn,
          "INSERT INTO messages (session_id, role, content, tool_calls, tool_call_id, name, inserted_at) " <>
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
          [
            session_id,
            to_string(msg.role),
            msg.content,
            encode(msg.tool_calls),
            msg.tool_call_id,
            msg.name,
            now
          ]
        )
      end)

      :ok
    end)
  end

  @impl true
  def load_session(%{database: database}, session_id) do
    with_conn(database, fn conn ->
      metadata_json =
        case query_rows(conn, "SELECT metadata FROM sessions WHERE id = ?", [session_id]) do
          [[json]] -> json
          [] -> "{}"
        end

      messages =
        query_rows(
          conn,
          "SELECT role, content, tool_calls, tool_call_id, name FROM messages " <>
            "WHERE session_id = ? ORDER BY id",
          [session_id]
        )
        |> Enum.map(&row_to_message/1)

      metadata = Jason.decode!(metadata_json)
      {:ok, %{messages: messages, metadata: metadata}}
    end)
  end

  @impl true
  def list_sessions(%{database: database}, _opts) do
    with_conn(database, fn conn ->
      sessions =
        query_rows(
          conn,
          "SELECT id, title, metadata, created_at, updated_at FROM sessions ORDER BY updated_at DESC"
        )
        |> Enum.map(fn [id, title, metadata, created_at, updated_at] ->
          %{
            id: id,
            title: title,
            metadata: Jason.decode!(metadata),
            created_at: created_at,
            updated_at: updated_at
          }
        end)

      {:ok, sessions}
    end)
  end

  @impl true
  def remember(%{database: database}, session_id, note) do
    with_conn(database, fn conn ->
      exec!(
        conn,
        "INSERT INTO memories (session_id, content, inserted_at) VALUES (?, ?, ?)",
        [session_id, note, now_iso()]
      )

      :ok
    end)
  end

  @impl true
  def recall(%{database: database}, session_id, _opts) do
    with_conn(database, fn conn ->
      {sql, params} =
        if session_id do
          {"SELECT content FROM memories WHERE session_id = ? ORDER BY id", [session_id]}
        else
          {"SELECT content FROM memories ORDER BY id", []}
        end

      notes =
        query_rows(conn, sql, params)
        |> Enum.map(fn [content] -> content end)
        |> Enum.join("\n\n---\n\n")

      {:ok, notes}
    end)
  end

  @impl true
  def write_trace(%{database: database}, session_id, run_id, event) do
    with_conn(database, fn conn ->
      exec!(
        conn,
        "INSERT INTO traces (run_id, session_id, type, payload, inserted_at) VALUES (?, ?, ?, ?, ?)",
        [run_id, session_id, to_string(event.type), Jason.encode!(event.payload), now_iso()]
      )

      :ok
    end)
  end

  @impl true
  def get_trace(%{database: database}, session_id, run_id) do
    with_conn(database, fn conn ->
      {where, params} =
        cond do
          run_id && session_id ->
            {"WHERE run_id = ? AND session_id = ?", [run_id, session_id]}

          run_id ->
            {"WHERE run_id = ?", [run_id]}

          session_id ->
            {"WHERE session_id = ?", [session_id]}

          true ->
            {"", []}
        end

      traces =
        query_rows(
          conn,
          "SELECT run_id, session_id, type, payload, inserted_at FROM traces #{where} ORDER BY id",
          params
        )
        |> Enum.map(fn [run_id, session_id, type, payload, inserted_at] ->
          %{
            run_id: run_id,
            session_id: session_id,
            type: String.to_existing_atom(type),
            payload: Jason.decode!(payload),
            inserted_at: inserted_at
          }
        end)

      {:ok, traces}
    end)
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp migrate(conn) do
    Initial.up()
    |> String.split(";", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.each(fn sql ->
      exec!(conn, sql)
    end)

    :ok
  end

  defp transaction(database, fun) do
    with_conn(database, fn conn ->
      exec!(conn, "BEGIN TRANSACTION")

      try do
        result = fun.(conn)
        exec!(conn, "COMMIT")
        result
      rescue
        error ->
          exec!(conn, "ROLLBACK")
          reraise error, __STACKTRACE__
      end
    end)
  end

  defp with_conn(database, fun) do
    {:ok, conn} = Sqlite.open(database)

    try do
      fun.(conn)
    after
      Sqlite.close(conn)
    end
  end

  defp query_rows(conn, stmt, args \\ []) do
    case Sqlite.exec(conn, stmt, args) |> Sqlite.rows() do
      {:ok, rows, _columns} -> rows
      {:error, message} -> raise "SQLite query failed: #{message}"
    end
  end

  defp exec!(conn, stmt, args \\ []) do
    case Sqlite.exec(conn, stmt, args) |> Sqlite.rows() do
      {:ok, _rows, _columns} -> :ok
      {:error, message} -> raise "SQLite exec failed: #{message}"
    end
  end

  defp row_to_message([role, content, tool_calls_json, tool_call_id, name]) do
    %Message{
      role: String.to_existing_atom(role),
      content: content,
      tool_calls: decode(tool_calls_json),
      tool_call_id: tool_call_id,
      name: name
    }
  end

  defp encode(nil), do: nil
  defp encode(value), do: Jason.encode!(value)

  defp decode(nil), do: nil
  defp decode(json), do: Jason.decode!(json)

  defp now_iso, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
