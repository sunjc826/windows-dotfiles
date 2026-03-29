# PermissionRequest Hook Design

## Goal

Automate Claude Code's permission prompts with a multi-tier strategy: log all
requests, auto-allow non-Bash tools, and gate Bash commands through an allowlist
+ LLM safety check.

## File Layout

```
windows-dotfiles/
  .claude/
    hooks/
      log-permission.sh      # Logs all permission requests
      bash-gatekeeper.sh     # Multi-tier Bash command gating
    logs/                    # Runtime logs (gitignored)
    settings.json            # Hook configuration
  .gitignore                 # Ignores .claude/logs/
```

## Hook Configuration (settings.json)

Three `PermissionRequest` entries:

1. **Logger** — matcher: `""` (all tools). Runs `log-permission.sh`. Async, never blocks.
2. **Non-Bash auto-allow** — matcher: `^(?!Bash$)` (everything except Bash). Returns `allow`.
3. **Bash gatekeeper** — matcher: `Bash`. Runs `bash-gatekeeper.sh`. Synchronous, can block.

## log-permission.sh

- Reads JSON from stdin via `jq`.
- Extracts: `tool_name`, `tool_input.command` (or `tool_input.file_path` for Edit/Write/Read), timestamp.
- Appends one line to `.claude/logs/permissions.log`:
  ```
  2026-03-29T14:30:00Z | Bash | git status
  ```
- Always exits 0 (never blocks).
- Creates the logs directory if missing.

## bash-gatekeeper.sh

### Tier 1: Regex Allowlist

Hardcoded patterns in the script. If the command matches any pattern, return
`allow` immediately.

**Read-only / inspection:**
- `git status`, `git log`, `git diff`, `git show`, `git branch`, `git remote`, `git tag`, `git rev-parse`
- `ls`, `cat`, `head`, `tail`, `pwd`, `echo`, `which`, `type`, `env`, `printenv`
- `wc`, `file`, `stat`, `find`, `grep`, `rg`, `jq`, `diff`, `sort`, `uniq`, `tr`, `cut`, `awk`, `sed` (read-only piped usage)

**Safe git write operations:**
- `git add`, `git commit`, `git branch`, `git checkout`, `git switch`, `git stash`, `git merge`, `git rebase`, `git cherry-pick`, `git tag`

**Build/dev tooling (scoped):**
- `npm run ...`, `npm test`, `npm install`, `npm ci`, `npm ls`, `npm outdated`, `npm audit`
- `npx prettier ...`, `npx eslint ...`
- `python <local-path>.py`, `python -m pytest`, `python -m unittest`
- `node <local-path>.js`
- `tsc`, `tsc --noEmit`

**Testing:**
- `npm test`, `pytest`, `jest`, `vitest`, `cargo test`

**Directory creation:**
- `mkdir`

### Tier 2: Haiku LLM Safety Check

If no regex matched, call the Anthropic Messages API with `claude-haiku-4-5-20251001`:

**System prompt:**
```
You are a security filter for shell commands executed by an AI coding assistant.
Evaluate the command for safety. Respond with ONLY a JSON object, no other text.

Rules (balanced policy):
- ALLOW: common development operations — file writes in project directories,
  package installs scoped to a project, compilation, formatting, linting,
  running project scripts, git operations that don't force-push or rewrite
  shared history.
- DENY: clearly destructive commands (rm -rf /, chmod -R 777 /), data
  exfiltration (curl/wget piping to external servers with local data),
  credential access (reading .env, ~/.ssh, /etc/shadow), force-push to
  main/master, system-wide package installs (sudo apt/brew install),
  cryptomining, reverse shells.
- ASK: anything ambiguous — commands you're unsure about, complex piped
  commands that mix safe and unsafe operations, operations on paths outside
  the project directory.

Response format:
{"decision": "allow|deny|ask", "reason": "brief explanation"}
```

**User message:** The raw command string.

**API call:** Uses `ANTHROPIC_API_KEY` from environment. Timeout: 10 seconds.

**Response parsing:**
- Extract `decision` and `reason` from Haiku's response.
- Map to hook output: `permissionDecision` = decision, `permissionDecisionReason` = reason.

### Tier 3: Fallback

If the API call fails (network error, missing API key, timeout, malformed response):
- Default to `ask` (let user decide).
- Log the failure.

## Log Directory

- Path: `windows-dotfiles/.claude/logs/`
- Gitignored via `.gitignore` at repo root.
- Created at runtime by `log-permission.sh` if missing.

## Environment Variables

- `ANTHROPIC_API_KEY` — required for Tier 2. Passed via `allowedEnvVars` in hook config.
- `CLAUDE_PROJECT_DIR` — used for log path resolution.

## Cross-Platform Notes

- Scripts use `#!/bin/bash` (Git Bash on Windows, native bash elsewhere).
- `jq` required on all machines.
- `curl` used for API calls (available in Git Bash).
- Scripts use LF line endings (enforce via `.gitattributes`).
