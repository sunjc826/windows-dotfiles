#!/bin/bash
set -euo pipefail

# Ensure WinGet-installed tools (jq, etc.) are on PATH in hook environment
export PATH="/c/Users/sunjc/AppData/Local/Microsoft/WinGet/Links:$PATH"

# --- Verbose tracing (set CLAUDE_HOOK_VERBOSE=1 to enable) ---
VERBOSE="${CLAUDE_HOOK_VERBOSE:-0}"
SCRIPT_DIR=$(realpath -- "$(dirname -- "${BASH_SOURCE[0]}")")
LOG_DIR="$(dirname "$SCRIPT_DIR")/logs"
mkdir -p "$LOG_DIR"
VERBOSE_LOG="$LOG_DIR/hook-trace.log"

vtrace() {
  if [ "$VERBOSE" = "1" ]; then
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*" >> "$VERBOSE_LOG"
  fi
}

vtrace "--- Hook invoked ---"

# --- Read stdin JSON once ---
INPUT="$(cat)"
vtrace "Raw input: $INPUT"

TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name // empty')"
vtrace "Tool name: $TOOL_NAME"

# Extract detail: command for Bash, file_path for file tools, tool_name as fallback
case "$TOOL_NAME" in
  Bash)
    DETAIL="$(echo "$INPUT" | jq -r '.tool_input.command // empty')"
    ;;
  Edit|Write|Read|Glob|Grep)
    DETAIL="$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')"
    ;;
  *)
    DETAIL="$TOOL_NAME"
    ;;
esac
vtrace "Detail: $DETAIL"

# --- Logging setup ---
LOG_FILE="$LOG_DIR/permissions.jsonl"

# --- Helper: log decision and output hook JSON ---
log_and_respond() {
  local decision="$1"
  local reason="$2"
  local ts
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  # Append JSON Lines log entry
  jq -n -c \
    --arg ts "$ts" \
    --arg tool "$TOOL_NAME" \
    --arg decision "$decision" \
    --arg detail "$DETAIL" \
    --arg reason "$reason" \
    '{ts: $ts, tool: $tool, decision: $decision, detail: $detail, reason: $reason}' \
    >> "$LOG_FILE"

  # Output hook response
  local output
  output="$(jq -n \
    --arg decision "$decision" \
    --arg reason "$reason" \
    '{
      hookSpecificOutput: {
        hookEventName: "PermissionRequest",
        decision: {
          behavior: $decision
        }
      }
    }')"

  vtrace "Hook JSON output: $output"
  echo "$output"
  exit 0
}

# --- Bash Tier 1: Regex Allowlist ---
check_allowlist() {
  local cmd="$1"

  # Strip leading whitespace and env var assignments (e.g. "FOO=bar cmd")
  local base_cmd
  base_cmd="$(echo "$cmd" | sed 's/^[[:space:]]*//' | sed 's/^[A-Za-z_][A-Za-z_0-9]*=[^ ]* *//')"

  local -a ALLOWED_PATTERNS=(
    # Read-only / inspection
    '^git (status|log|diff|show|branch|remote|tag|rev-parse|rev-list|describe|ls-files|ls-tree|cat-file|shortlog|reflog|blame|whatchanged)( |$)'
    '^(ls|cat|head|tail|pwd|echo|which|type|env|printenv|true|false)( |$)'
    '^(wc|file|stat|find|grep|rg|jq|diff|sort|uniq|tr|cut|awk|sed)( |$)'
    '^(dirname|basename|realpath|readlink)( |$)'

    # Safe git write operations
    '^git (add|commit|branch|checkout|switch|stash|merge|rebase|cherry-pick|tag|restore|reset)( |$)'

    # Build/dev tooling (scoped)
    '^npm (run|test|install|ci|ls|outdated|audit|exec|pkg|version|view|info|explain)( |$)'
    '^npx (prettier|eslint)( |$)'
    '^python [^ ]*\.py( |$)'
    '^python -m (pytest|unittest)( |$)'
    '^node [^ ]*\.js( |$)'
    '^tsc( |$)'

    # Testing
    '^(pytest|jest|vitest|cargo test)( |$)'

    # Directory creation
    '^mkdir( |$)'

    # Common safe utilities
    '^(touch|cp|mv|chmod|date|uname|whoami|hostname|id)( |$)'
    '^(tar|zip|unzip|gzip|gunzip)( |$)'
    '^rm -f /tmp/cc_'
  )

  for pattern in "${ALLOWED_PATTERNS[@]}"; do
    if echo "$base_cmd" | grep -qE "$pattern"; then
      return 0
    fi
  done

  return 1
}

# --- Bash Tier 2: Haiku LLM Safety Check ---
check_with_haiku() {
  local cmd="$1"

  # Bail if claude CLI not available
  if ! command -v claude &>/dev/null; then
    echo "ask|claude CLI not found"
    return 0
  fi

  local system_prompt
  system_prompt='You are a security filter for shell commands executed by an AI coding assistant on Windows (Git Bash / MINGW64). Evaluate the command for safety.

IMPORTANT CONTEXT: This runs on Windows where the Claude Code Bash tool has a known stdout bug — any command producing stdout fails. The standard workaround is appending "> /tmp/cc_output.txt 2>&1; true" to commands. This redirection pattern is NORMAL and EXPECTED, not a sign of data exfiltration. /tmp maps to a local temp directory. Treat this suffix as harmless boilerplate.

Similarly, "cd /path && command" is a normal pattern for running commands in a specific project directory, not a path resolution bypass.

Rules:
- ALLOW: common dev operations — file reads/writes in project dirs, scoped package installs, compilation, formatting, linting, running project scripts, git operations that dont force-push or rewrite shared history. Commands prefixed with "cd <project-dir> &&" are fine.
- DENY: destructive commands (rm -rf /, chmod -R 777 /), data exfiltration (curl/wget piping local data to EXTERNAL servers), credential access (.env, ~/.ssh, /etc/shadow), force-push to main/master, system-wide installs (sudo apt/brew install), cryptomining, reverse shells.
- ASK: anything ambiguous, complex piped commands mixing safe and unsafe operations.'

  local json_schema='{"type":"object","properties":{"decision":{"type":"string","enum":["allow","deny","ask"]},"reason":{"type":"string"}},"required":["decision","reason"]}'

  # Use claude CLI with -p (print mode) — uses existing subscription auth,
  # and -p mode does NOT trigger PermissionRequest hooks (no infinite recursion).
  # --json-schema enforces structured output in .structured_output field.
  local response
  response="$(echo "$cmd" | claude -p \
    --model haiku \
    --system-prompt "$system_prompt" \
    --output-format json \
    --json-schema "$json_schema" \
    --no-session-persistence 2>/dev/null)" || {
    echo "ask|claude CLI call failed"
    return 0
  }

  # Extract structured output from claude JSON response
  local haiku_decision haiku_reason
  haiku_decision="$(echo "$response" | jq -r '.structured_output.decision // empty' 2>/dev/null)" || true
  haiku_reason="$(echo "$response" | jq -r '.structured_output.reason // empty' 2>/dev/null)" || true

  # Validate decision is one of allow/deny/ask
  case "$haiku_decision" in
    allow|deny|ask)
      echo "${haiku_decision}|Haiku: ${haiku_reason}"
      ;;
    *)
      echo "ask|Haiku returned invalid decision: $haiku_decision"
      ;;
  esac
}

# --- Route by tool name ---
case "$TOOL_NAME" in
  Bash)
    if check_allowlist "$DETAIL"; then
      vtrace "Decision: ALLOW via allowlist"
      log_and_respond "allow" "allowlist"
    else
      vtrace "Not on allowlist, invoking Haiku tier-2 check..."
      haiku_result="$(check_with_haiku "$DETAIL")"
      haiku_decision="${haiku_result%%|*}"
      haiku_reason="${haiku_result#*|}"
      vtrace "Haiku result: decision=$haiku_decision reason=$haiku_reason"
      log_and_respond "$haiku_decision" "$haiku_reason"
    fi
    ;;
  *)
    vtrace "Decision: ALLOW (non-bash auto-allow)"
    log_and_respond "allow" "non-bash auto-allow"
    ;;
esac
