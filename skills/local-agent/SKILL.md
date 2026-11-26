---
name: local-agent
description: Hand a task to a local-LLM Claude Code agent started with the claude-local command, either one-shot in the background or as a session you can message. Use only when the user refers to it - local-agent, local agent, local worker, local model, local LLM, claude-local or claude-local-agent - or asks to offload or delegate work locally, or when CLAUDE.md says to. Do not use for a plain request for a subagent, agent or worker, for web or service workers, or for running something on this machine ("run the tests locally").
---

# Local agent (claude-local)

`claude-local` is `claude` running against a local LLM. It is a script next to `claude` that loads `~/.claude/local-agent/settings.json` (server URL, model, token) instead of `~/.claude/settings.json`, and passes all arguments through. Never read, print, or copy that file: it holds the token. If the command is not found, ask the user to run the setup script (see Setup).

The built-in Agent tool cannot use the local model: its subagents run on this session's cloud endpoint. A local worker is therefore always a separate `claude-local` process. A plain request for a "subagent" or "agent" means the built-in Agent tool, not this skill.

## Setup

Setup asks for a token, so the user runs it in their own terminal. Do not run it for them or collect these values in chat.

- Windows: `irm https://raw.githubusercontent.com/EduardSmilyi/claude-local-agent/main/scripts/install.ps1 | iex`
- Linux and macOS: `curl -fsSL https://raw.githubusercontent.com/EduardSmilyi/claude-local-agent/main/scripts/install.sh | bash`

Running it again updates the installed files. From a clone of the repository, `scripts/setup.ps1 -Configure` or `bash scripts/setup.sh --configure` asks for the settings again.

## What to delegate

Delegate: investigation, mechanical refactors, boilerplate, tests for existing behavior, and code from an already-decided spec scoped to named files.

Keep: design, security-sensitive code, permission or config changes, git operations, and final review. Rules in the project's `CLAUDE.md` take precedence.

## 1. Write the brief

The worker starts with no memory of this conversation. Write a file in the scratchpad directory with:

- Goal, and what done looks like.
- The exact files in scope.
- The project rules that apply (from `CLAUDE.md` or `AGENTS.md`).
- A request to end with the files changed and anything it was unsure about.

Refer to the brief and its folder by full long paths. A short Windows path such as `NAME~1` makes the worker ask for a permission it cannot get.

## 2. One-shot worker (default)

| Task | Flags |
| :--- | :--- |
| Investigation | `--allowedTools "Read,Grep,Glob" --disallowedTools "Edit,Write,NotebookEdit,Bash,PowerShell"` |
| Edits | `--permission-mode acceptEdits --allowedTools "Read,Grep,Glob" --disallowedTools "Bash,PowerShell"` |

Run with the shell tool (PowerShell on Windows, Bash on Linux and macOS) and `run_in_background: true`. You are notified when it exits, and the output is the worker's final answer. Short tasks can run in the foreground.

```
claude-local -p "Read the brief at <brief.md> and carry it out." --add-dir "<brief folder>" <flags>
```

## 3. Attached session

Use when the task needs follow-ups, or the user wants to watch or steer the worker. A background session must not run in auto mode: its safety check does not work through a local server, so actions are refused.

| Task | Flags |
| :--- | :--- |
| Investigation | `--permission-mode dontAsk --allowedTools "Read,Grep,Glob,SendMessage" --disallowedTools "Edit,Write,NotebookEdit,Bash,PowerShell"` |
| Edits | `--permission-mode acceptEdits --allowedTools "Read,Grep,Glob,SendMessage" --disallowedTools "Bash,PowerShell"` |

```
claude-local --bg "Read the brief at <brief.md> and carry it out." --name "local-<task>" --add-dir "<brief folder>" <flags>
```

- **Message it:** the session appears in `ListAgents` under its name. Send follow-ups with `SendMessage`, with `notify_when_idle: true`. It keeps its context between messages.
- **Get replies:** the worker's plain output does not reach this session. Ask it to reply with `SendMessage`, using the incoming message's `from` value as `to`.
- **User attaches:** `claude-local attach <id>` in a terminal.
- **Inspect:** `claude-local logs <id>` and `claude-local agents --json`.
- **Clean up:** `claude-local stop <id>` when the work is accepted. Stop only sessions you started.

Never ask a worker to do something that was denied or blocked in this session.

## 4. Permissions and review

- Use edit flags only when the brief names the files. Nothing technically limits edits to those files.
- Do not give the worker shell access: it must not commit, branch, or push.
- Treat the worker's claims as unverified. Check `git status` and `git diff` for changes outside the brief, and run the project's checks where possible.
- If the worker fails twice on the same task, take the task back.

## Troubleshooting

| Symptom | Check |
| :--- | :--- |
| `claude-local` not found | Run the setup script. |
| `401 missing or wrong API key` | The installed launcher must remove `CLAUDE_CODE_ENTRYPOINT`. Run the setup script to update it. Otherwise check the token with `-Configure`. |
| `settings file not found` | `~/.claude/local-agent/settings.json`, or the `CLAUDE_LOCAL_SETTINGS` override. |
| `Auto mode can't check actions in this session` | The worker started in auto mode. Stop it and set `--permission-mode`. |
| Connection errors | The local server in `ANTHROPIC_BASE_URL` is not running. |
| `claude.ai connectors are disabled` warning | Expected. The worker uses a local token. |
