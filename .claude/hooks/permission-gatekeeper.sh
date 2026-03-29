#!/bin/bash
set -euo pipefail

# --- Read stdin JSON once ---
INPUT="$(cat)"
TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name // empty')"

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

# --- Logging setup ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$(dirname "$SCRIPT_DIR")/logs"
mkdir -p "$LOG_DIR"
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
  jq -n \
    --arg decision "$decision" \
    --arg reason "$reason" \
    '{
      hookSpecificOutput: {
        hookEventName: "PermissionRequest",
        decision: {
          behavior: $decision
        }
      }
    }'

  # Exit code: 0 for allow, 2 for deny/ask
  if [ "$decision" = "allow" ]; then
    exit 0
  else
    exit 0
  fi
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

  # Bail if no API key
  if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    echo "ask|no API key available"
    return 0
  fi

  local system_prompt
  system_prompt='You are a security filter for shell commands executed by an AI coding assistant.
Evaluate the command for safety. Respond with ONLY a JSON object, no other text.

Rules (balanced policy):
- ALLOW: common development operations — file writes in project directories, package installs scoped to a project, compilation, formatting, linting, running project scripts, git operations that dont force-push or rewrite shared history.
- DENY: clearly destructive commands (rm -rf /, chmod -R 777 /), data exfiltration (curl/wget piping to external servers with local data), credential access (reading .env, ~/.ssh, /etc/shadow), force-push to main/master, system-wide package installs (sudo apt/brew install), cryptomining, reverse shells.
- ASK: anything ambiguous — commands you are unsure about, complex piped commands that mix safe and unsafe operations, operations on paths outside the project directory.

Response format:
{"decision": "allow|deny|ask", "reason": "brief explanation"}'

  local request_body
  request_body="$(jq -n -c \
    --arg system "$system_prompt" \
    --arg cmd "$cmd" \
    '{
      model: "claude-haiku-4-5-20251001",
      max_tokens: 150,
      system: $system,
      messages: [{role: "user", content: $cmd}]
    }')"

  local response
  response="$(curl -s --max-time 10 \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d "$request_body" \
    "https://api.anthropic.com/v1/messages" 2>/dev/null)" || {
    echo "ask|API call failed"
    return 0
  }

  # Extract text content from API response
  local text_content
  text_content="$(echo "$response" | jq -r '.content[0].text // empty' 2>/dev/null)" || {
    echo "ask|failed to parse API response"
    return 0
  }

  if [ -z "$text_content" ]; then
    echo "ask|empty API response"
    return 0
  fi

  # Parse Haiku's JSON decision
  local haiku_decision haiku_reason
  haiku_decision="$(echo "$text_content" | jq -r '.decision // empty' 2>/dev/null)" || true
  haiku_reason="$(echo "$text_content" | jq -r '.reason // empty' 2>/dev/null)" || true

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
      log_and_respond "allow" "allowlist"
    else
      # Tier 2: Ask Haiku
      haiku_result="$(check_with_haiku "$DETAIL")"
      haiku_decision="${haiku_result%%|*}"
      haiku_reason="${haiku_result#*|}"
      log_and_respond "$haiku_decision" "$haiku_reason"
    fi
    ;;
  *)
    log_and_respond "allow" "non-bash auto-allow"
    ;;
esac
