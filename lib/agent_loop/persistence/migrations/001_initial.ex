defmodule AgentLoop.Persistence.Migrations.Initial do
  @moduledoc """
  Initial SQLite schema for sessions, messages, memories, and traces.
  """

  def up do
    """
    CREATE TABLE IF NOT EXISTS sessions (
      id TEXT PRIMARY KEY,
      title TEXT,
      metadata TEXT NOT NULL DEFAULT '{}',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS messages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id TEXT NOT NULL,
      role TEXT NOT NULL,
      content TEXT,
      tool_calls TEXT,
      tool_call_id TEXT,
      name TEXT,
      inserted_at TEXT NOT NULL,
      FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
    );

    CREATE INDEX IF NOT EXISTS idx_messages_session ON messages(session_id, inserted_at);

    CREATE TABLE IF NOT EXISTS memories (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id TEXT,
      content TEXT NOT NULL,
      inserted_at TEXT NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_memories_session ON memories(session_id, inserted_at);

    CREATE TABLE IF NOT EXISTS traces (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      run_id TEXT,
      session_id TEXT,
      type TEXT NOT NULL,
      payload TEXT NOT NULL,
      inserted_at TEXT NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_traces_run ON traces(run_id, inserted_at);
    CREATE INDEX IF NOT EXISTS idx_traces_session ON traces(session_id, inserted_at);
    """
  end
end
