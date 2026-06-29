# Changelog

## 0.2.0

- Added SQLite-backed persistence for sessions, memory, and traces.
- Added `AgentLoop.Persistence` behaviour with `NoOp` and `SQLite` adapters.
- Added `session_id` and `run_id` to `RunRequest`.
- Added `persistence` and `trace` options to `LoopConfig`.
- Updated `memory` tool to use persistence.
- Added `--session`, `--memory-db`, and `--trace` CLI flags.

## 0.1.0

- Initial release.
- Functional think → act → observe agent loop.
- Workspace-aware coding tools: `read_file`, `list_files`, `write_file`, `edit_file`, `grep`, `shell_exec`, `fetch_url`, `memory`.
- OpenAI-compatible and DeepSeek providers.
- CLI via `mix agent.run`.
