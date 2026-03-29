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

# --- Route by tool name ---
case "$TOOL_NAME" in
  Bash)
    # Bash gating handled in Task 3 and Task 4 — placeholder for now
    log_and_respond "ask" "not yet implemented"
    ;;
  *)
    log_and_respond "allow" "non-bash auto-allow"
    ;;
esac
