---
name: new-hook
description: Use when creating, modifying, or debugging Claude Code hooks. Covers hook events, matchers, input/output schemas, command/http/prompt/agent types, and cross-platform scripting.
user-invocable: false
---

# Claude Code Hooks

## Overview

Hooks are shell commands, HTTP endpoints, or LLM prompts that execute
automatically at specific points in Claude Code's lifecycle. They provide
**deterministic control** — certain actions always happen rather than relying on
the LLM to choose them.

## Where Hooks Live

Hooks are configured in `settings.json` under the `"hooks"` key.

| Location | Scope | In VCS? |
|----------|-------|---------|
| `~/.claude/settings.json` | All projects | No (local) |
| `<project>/.claude/settings.json` | One project | Yes |
| `<project>/.claude/settings.local.json` | One project | No (gitignored) |
| Plugin `hooks/hooks.json` | When plugin enabled | Yes |

### User-Level Hooks (this machine)

User-level hooks are managed in the **windows-dotfiles** repo at
`C:\Users\sunjc\Documents\Projects\windows-dotfiles\.claude\settings.json`.
The installer symlinks this into `~/.claude/settings.json`, so hooks defined
there follow you across machines.

Hook **scripts** should also live in the dotfiles repo (e.g.,
`windows-dotfiles/.claude/hooks/`) and be referenced with portable paths.

## Configuration Structure

```jsonc
{
  "hooks": {
    "EventName": [
      {
        "matcher": "regex-pattern",   // filter when hook fires (optional)
        "hooks": [
          {
            "type": "command",        // command | http | prompt | agent
            "command": "script.sh",
            "if": "Bash(git *)",      // conditional (permission rule syntax)
            "timeout": 600,           // seconds
            "once": false,            // run only once per session
            "statusMessage": "..."    // display to user
          }
        ]
      }
    ]
  }
}
```

## Hook Types

### Command

```jsonc
{
  "type": "command",
  "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/script.sh",
  "async": false,   // true = fire-and-forget
  "shell": "bash"
}
```

### HTTP

```jsonc
{
  "type": "http",
  "url": "http://localhost:8080/hooks",
  "headers": { "Authorization": "Bearer $MY_TOKEN" },
  "allowedEnvVars": ["MY_TOKEN"],
  "timeout": 30
}
```

### Prompt (LLM)

```jsonc
{
  "type": "prompt",
  "prompt": "Check if this is safe: $ARGUMENTS",
  "model": "claude-haiku-4-5-20251001",  // default: haiku
  "timeout": 30
}
```

### Agent

```jsonc
{
  "type": "agent",
  "prompt": "Validate this operation: $ARGUMENTS",
  "model": "claude-sonnet-4-6",
  "timeout": 60
}
```

## Events Reference

### Can Block

| Event | Matches On | Description |
|-------|-----------|-------------|
| `UserPromptSubmit` | — | User submits a prompt |
| `PreToolUse` | Tool name | Before tool execution |
| `PermissionRequest` | Tool name | Permission dialog shown |
| `PostToolUse` | Tool name | After tool succeeds |
| `Stop` | — | Claude finishes responding |
| `TaskCreated` | — | Task being created |
| `TaskCompleted` | — | Task marked complete |
| `ConfigChange` | Config source | Settings file changes |
| `WorktreeCreate` | — | Worktree created |
| `Elicitation` | MCP server | MCP requests user input |
| `ElicitationResult` | MCP server | User responds to MCP |

### Cannot Block

| Event | Matches On | Description |
|-------|-----------|-------------|
| `SessionStart` | Source (`startup`, `resume`, `clear`, `compact`) | New/resumed session |
| `SessionEnd` | Reason (`clear`, `resume`, `logout`, etc.) | Session terminates |
| `InstructionsLoaded` | Load reason | CLAUDE.md or rules loaded |
| `PostToolUseFailure` | Tool name | After tool fails |
| `Notification` | Type (`permission_prompt`, `idle_prompt`, etc.) | Notification event |
| `PreCompact` | Trigger (`manual`, `auto`) | Before context compaction |
| `PostCompact` | Trigger | After compaction |
| `CwdChanged` | — | Working directory changes |
| `FileChanged` | Filename (basename) | Watched file changes |

## Matchers

Matchers are **regex patterns** matching against event-specific fields.

```jsonc
// Single tool
{ "matcher": "Bash" }

// Multiple tools (alternation)
{ "matcher": "Edit|Write" }

// All MCP tools
{ "matcher": "mcp__.*" }

// Specific MCP server
{ "matcher": "mcp__github__.*" }

// Empty = match all
{ "matcher": "" }
```

### The `if` Field (Fine-Grained Filtering)

Uses permission rule syntax to match tool name + arguments:

```jsonc
{
  "matcher": "Bash",
  "hooks": [{
    "if": "Bash(git *)",      // only git commands
    "command": "check-git.sh"
  }]
}
```

Other examples: `"Edit(*.ts)"`, `"Read(/sensitive/*)"`.

## Input (stdin)

All hooks receive JSON on stdin with common fields:

```jsonc
{
  "session_id": "abc123",
  "transcript_path": "/path/to/transcript.jsonl",
  "cwd": "/current/working/dir",
  "permission_mode": "default",
  "hook_event_name": "PreToolUse"
}
```

Event-specific additions:

- **PreToolUse / PostToolUse**: `tool_name`, `tool_input`, `tool_use_id` (PostToolUse adds `tool_result`)
- **UserPromptSubmit**: `prompt`
- **SessionStart**: `source`
- **FileChanged**: `file_path`, `file_name`
- **CwdChanged**: `cwd`, `previous_cwd`
- **Stop**: `stop_hook_active` (true if this is a re-check — exit early to avoid infinite loops)

## Output (stdout + exit code)

### Exit Codes

| Code | Meaning |
|------|---------|
| **0** | Success — parse stdout for JSON |
| **2** | Block — stderr shown to Claude as feedback |
| **Other** | Non-blocking error — stderr in verbose mode only |

### JSON Output for PreToolUse

```jsonc
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow|deny|ask",
    "permissionDecisionReason": "Why",
    "updatedInput": { "command": "modified command" },
    "additionalContext": "Extra info for Claude"
  }
}
```

### JSON Output for PermissionRequest

```jsonc
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "allow|deny",
      "updatedInput": { "command": "safe version" }
    }
  }
}
```

### JSON Output for Stop

```jsonc
{
  "decision": "block",
  "reason": "Tests not passing yet"
}
```

### Plain Text Output (SessionStart)

Stdout text is injected into Claude's context. Use for reminders after compaction.

## Environment Variables

```bash
$CLAUDE_PROJECT_DIR    # Project root
$CLAUDE_PLUGIN_ROOT    # Plugin install dir
$CLAUDE_PLUGIN_DATA    # Plugin persistent data dir
$CLAUDE_ENV_FILE       # Write env vars here (SessionStart/CwdChanged/FileChanged)
```

## Cross-Platform Hook Scripts

Since hooks must work on Windows (Git Bash), macOS, and Linux:

- **Use `bash` scripts** — Git Bash provides bash on Windows.
- **Use `jq`** for JSON parsing — ensure it's installed on all machines.
- **Use `$CLAUDE_PROJECT_DIR`** instead of hardcoded paths.
- **Avoid platform-specific commands** — no `osascript` (macOS-only), no `powershell.exe` (Windows-only) unless guarded:

```bash
#!/bin/bash
case "$(uname -s)" in
  MINGW*|MSYS*) # Windows (Git Bash)
    powershell.exe -Command "..." ;;
  Darwin)        # macOS
    osascript -e '...' ;;
  Linux)
    notify-send '...' ;;
esac
```

- **Make scripts executable**: `chmod +x script.sh`.
- **Use LF line endings** for all `.sh` files (add `*.sh text eol=lf` to `.gitattributes`).

## Common Patterns

### Block Dangerous Commands

```jsonc
// settings.json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Bash",
      "hooks": [{
        "type": "command",
        "if": "Bash(rm -rf *)",
        "command": "echo '{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"Destructive command blocked\"}}'"
      }]
    }]
  }
}
```

### Auto-Format After Edits

```jsonc
{
  "hooks": {
    "PostToolUse": [{
      "matcher": "Edit|Write",
      "hooks": [{
        "type": "command",
        "command": "jq -r '.tool_input.file_path' | xargs npx prettier --write",
        "async": true
      }]
    }]
  }
}
```

### Re-Inject Context After Compaction

```jsonc
{
  "hooks": {
    "SessionStart": [{
      "matcher": "compact",
      "hooks": [{
        "type": "command",
        "command": "cat \"$CLAUDE_PROJECT_DIR\"/.claude/compaction-context.md"
      }]
    }]
  }
}
```

### Desktop Notifications (Cross-Platform)

```jsonc
{
  "hooks": {
    "Notification": [{
      "matcher": "",
      "hooks": [{
        "type": "command",
        "command": "\"$HOME\"/.claude/hooks/notify.sh"
      }]
    }]
  }
}
```

Where `notify.sh` uses the `uname` platform-detection pattern above.

## Gotchas

| Issue | Fix |
|-------|-----|
| Hook not firing | Run `/hooks` to verify registration; matchers are case-sensitive |
| JSON parse failure | Shell profile `echo` statements prepend junk — wrap in `if [[ $- == *i* ]]` |
| Stop hook infinite loop | Check `stop_hook_active` in input; exit early if true |
| PermissionRequest ignored in `-p` mode | Use `PreToolUse` instead for non-interactive |
| PostToolUse can't undo | Use `PreToolUse` to block before execution |
| Script not found | Use absolute paths or `$CLAUDE_PROJECT_DIR`; ensure `chmod +x` |
| Windows line endings break script | Use `*.sh text eol=lf` in `.gitattributes` |
