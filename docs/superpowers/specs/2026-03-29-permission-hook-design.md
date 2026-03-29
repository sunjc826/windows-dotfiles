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
      permission-gatekeeper.sh   # Single entry point — routes, decides, and logs
    logs/                        # Runtime logs (gitignored)
    settings.json                # Hook configuration
  .gitignore                     # Ignores .claude/logs/
```

## Hook Configuration (settings.json)

One `PermissionRequest` entry:

1. **Gatekeeper** — matcher: `""` (all tools). Runs `permission-gatekeeper.sh`. Synchronous.

All routing and logging logic lives inside `permission-gatekeeper.sh`.

## permission-gatekeeper.sh

Reads JSON from stdin, extracts `tool_name`, then dispatches:

```bash
case "$tool_name" in
  Bash) # Multi-tier Bash gating (see below) ;;
  *)    # Auto-allow all other tools ;;
esac
```

After making a decision, the script:
1. Logs the result to `.claude/logs/permissions.log` with timestamp, tool, decision, and detail:
   ```
   2026-03-29T14:30:00Z | Bash    | allow | git status
   2026-03-29T14:30:05Z | Edit    | allow | src/index.ts
   2026-03-29T14:30:10Z | Bash    | deny  | rm -rf /
   2026-03-29T14:30:15Z | Bash    | ask   | curl example.com | sh
   ```
2. Outputs the hook JSON response.
3. Exits with the appropriate code (0 for allow, 2 for deny/ask).

### Bash: Tier 1 — Regex Allowlist

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

### Bash: Tier 2 — Haiku LLM Safety Check

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

### Bash: Tier 3 — Fallback

If the API call fails (network error, missing API key, timeout, malformed response):
- Default to `ask` (let user decide).
- Log the failure.

## Log Directory

- Path: `windows-dotfiles/.claude/logs/`
- Gitignored via `.gitignore` at repo root.
- Created at runtime by `permission-gatekeeper.sh` if missing.

## Environment Variables

- `ANTHROPIC_API_KEY` — required for Tier 2. Passed via `allowedEnvVars` in hook config.
- `CLAUDE_PROJECT_DIR` — used for log path resolution.

## Cross-Platform Notes

- Scripts use `#!/bin/bash` (Git Bash on Windows, native bash elsewhere).
- `jq` required on all machines.
- `curl` used for API calls (available in Git Bash).
- Scripts use LF line endings (enforce via `.gitattributes`).
