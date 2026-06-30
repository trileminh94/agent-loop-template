# Kimi Code Clone

A small example application built on top of `agent_loop`.

It shows how to use the library to build a supervised CLI coding assistant with:

- A `GenServer` session manager
- SQLite-backed session persistence
- Approval prompts for destructive tools (`shell_exec`, `write_file`)
- Workspace-restricted file tools

## Usage

From this directory:

```bash
export OPENAI_API_KEY=sk-...

mix deps.get
mix kimi.run "list files and summarize this project" --session demo
```

Target another workspace:

```bash
mix kimi.run "find TODOs" --workspace /path/to/project --session todos
```

Use DeepSeek:

```bash
export OPENAI_API_KEY=$DEEPSEEK_API_KEY
mix kimi.run "explain README.md" --base-url https://api.deepseek.com --model deepseek-chat
```

## Project structure

```
lib/
├── kimi_code_clone/
│   ├── application.ex       # Supervisor
│   ├── session.ex           # GenServer wrapper around AgentLoop
│   ├── prompts.ex           # System prompts
│   ├── approval.ex          # Approval prompts
│   └── tools/
│       ├── registry.ex      # Tool registry builder
│       ├── shell_exec.ex    # Approval wrapper
│       └── write_file.ex    # Approval wrapper
└── mix/tasks/kimi.run.ex    # CLI entry point
```

## Extending

- Add MCP servers in `Session.init/1` via `LoopConfig` `mcp_servers:`.
- Add more approval wrappers in `KimiCodeClone.Tools.*`.
- Replace the blocking `IO.gets` approval with a TUI or web UI.
