#!/bin/bash
# Ralph Wiggum - Long-running AI agent loop
# Usage: ./ralph.sh [--tool amp|claude] [--no-prompt] [max_iterations]

set -e

# Parse arguments
TOOL="claude"  # Default to claude
MAX_ITERATIONS=10
NO_PROMPT=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --tool)
      TOOL="$2"
      shift 2
      ;;
    --tool=*)
      TOOL="${1#*=}"
      shift
      ;;
    --no-prompt)
      NO_PROMPT=true
      shift
      ;;
    *)
      # Assume it's max_iterations if it's a number
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        MAX_ITERATIONS="$1"
      fi
      shift
      ;;
  esac
done

# Validate tool choice
if [[ "$TOOL" != "amp" && "$TOOL" != "claude" ]]; then
  echo "Error: Invalid tool '$TOOL'. Must be 'amp' or 'claude'."
  exit 1
fi

# SCRIPT_DIR is where ralph.sh, prompt.md, and CLAUDE.md live
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# WORK_DIR is the current directory where prd.json should be
WORK_DIR="$(pwd)"

PRD_FILE="$WORK_DIR/prd.json"
PROGRESS_FILE="$WORK_DIR/progress.txt"
ARCHIVE_DIR="$WORK_DIR/archive"
LAST_BRANCH_FILE="$WORK_DIR/.last-branch"
STATUS_FILE="$WORK_DIR/.ralph-status"
OUTPUT_LOG="$WORK_DIR/.ralph-output.log"

# Check if prd.json exists in current directory
if [ ! -f "$PRD_FILE" ]; then
  echo "Error: prd.json not found in current directory: $WORK_DIR"
  echo "Please run ralph from a directory containing prd.json"
  exit 1
fi

# Display PRD summary
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                         RALPH STARTING                          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "📋 Project: $(jq -r '.project' "$PRD_FILE")"
echo "🌿 Branch: $(jq -r '.branchName' "$PRD_FILE")"
echo "📝 Stories: $(jq -r '.userStories | length' "$PRD_FILE") total"
echo "✅ Completed: $(jq -r '[.userStories[] | select(.passes == true)] | length' "$PRD_FILE")"
echo "⏳ Pending: $(jq -r '[.userStories[] | select(.passes == false)] | length' "$PRD_FILE")"
echo ""
echo "🛠️  Tool: $TOOL"
echo "🔄 Max iterations: $MAX_ITERATIONS"
echo "📂 Working directory: $WORK_DIR"
echo "💡 Check status anytime: cat $STATUS_FILE"
echo "💡 View live output: tail -f $OUTPUT_LOG"
echo ""

if [ "$NO_PROMPT" = false ]; then
  # Check if stdin is a terminal (interactive)
  if [ -t 0 ]; then
    read -p "❓ Continue? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "🛑 Cancelled by user"
      exit 1
    fi
  else
    # Non-interactive: auto-continue
    echo "💡 Non-interactive mode, auto-continuing..."
  fi
fi

# Archive previous run if branch changed
if [ -f "$PRD_FILE" ] && [ -f "$LAST_BRANCH_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  LAST_BRANCH=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")

  if [ -n "$CURRENT_BRANCH" ] && [ -n "$LAST_BRANCH" ] && [ "$CURRENT_BRANCH" != "$LAST_BRANCH" ]; then
    # Archive the previous run
    DATE=$(date +%Y-%m-%d)
    # Strip "ralph/" prefix from branch name for folder
    FOLDER_NAME=$(echo "$LAST_BRANCH" | sed 's|^ralph/||')
    ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$FOLDER_NAME"

    echo "📦 Archiving previous run: $LAST_BRANCH"
    mkdir -p "$ARCHIVE_FOLDER"
    [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
    echo "   Archived to: $ARCHIVE_FOLDER"

    # Reset progress file for new run
    echo "# Ralph Progress Log" > "$PROGRESS_FILE"
    echo "Started: $(date)" >> "$PROGRESS_FILE"
    echo "---" >> "$PROGRESS_FILE"
  fi
fi

# Track current branch
if [ -f "$PRD_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  if [ -n "$CURRENT_BRANCH" ]; then
    echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
  fi
fi

# Initialize progress file if it doesn't exist
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Ralph Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

# Function to display current status
display_status() {
  echo ""
  echo "📊 Current status:"
  jq -r '.userStories[] | "  [\(.id)] \(.title) - \(.passes | if . then "✅" else "⏳" end) (\(.model.providerName // "default"))"' "$PRD_FILE"
  echo ""
}

# Start status refresh in background
# Uses fswatch if available, otherwise polls file modification time
start_status_refresh() {
  local last_mtime=$(stat -f "%m" "$PRD_FILE" 2>/dev/null || stat -c "%Y" "$PRD_FILE" 2>/dev/null || echo 0)

  if command -v fswatch >/dev/null 2>&1; then
    # Use fswatch (event-based)
    (
      fswatch -o "$PRD_FILE" | while read -r num; do
        # Only refresh if this is not the first event (initial fswatch start)
        if [ "$num" -gt 1 ]; then
          echo ""
          echo "🔄 [Status updated]"
          display_status
          echo "🤖 $TOOL still running..."
        fi
      done
    ) &
    STATUS_PID=$!
    echo "📡 Status refresh: using fswatch (event-based)"
  else
    # Fallback: poll file modification time every 2 seconds
    (
      while true; do
        sleep 2
        local current_mtime=$(stat -f "%m" "$PRD_FILE" 2>/dev/null || stat -c "%Y" "$PRD_FILE" 2>/dev/null || echo 0)
        if [ "$current_mtime" != "$last_mtime" ]; then
          last_mtime="$current_mtime"
          echo ""
          echo "🔄 [Status updated]"
          display_status
          echo "🤖 $TOOL still running..."
        fi
      done
    ) &
    STATUS_PID=$!
    echo "📡 Status refresh: using polling (fallback)"
  fi
}

# Cleanup background process and status file on exit
cleanup() {
  if [ -n "$STATUS_PID" ]; then
    kill "$STATUS_PID" 2>/dev/null || true
    wait "$STATUS_PID" 2>/dev/null || true
  fi
  rm -f "$STATUS_FILE" 2>/dev/null || true
}

# Cleanup between iterations
cleanup_iter() {
  if [ -n "$STATUS_PID" ]; then
    kill "$STATUS_PID" 2>/dev/null || true
    wait "$STATUS_PID" 2>/dev/null || true
  fi
  STATUS_PID=""
}

trap cleanup EXIT

echo ""
echo "🚀 Starting Ralph..."
echo ""

for i in $(seq 1 $MAX_ITERATIONS); do
  echo ""
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║  ITERATION $i of $MAX_ITERATIONS ($TOOL)                          ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo "⏰ Started: $(date)"
  echo ""

  # Show initial status
  display_status

  # Start background status refresh
  start_status_refresh

  # Read current story's model config (highest priority story with passes: false)
  STORY_ID=$(jq -r '[.userStories[] | select(.passes == false)] | sort_by(.priority) | .[0].id // empty' "$PRD_FILE")
  STORY_TITLE=$(jq -r '[.userStories[] | select(.passes == false)] | sort_by(.priority) | .[0].title // empty' "$PRD_FILE")
  PROVIDER_NAME=$(jq -r '[.userStories[] | select(.passes == false)] | sort_by(.priority) | .[0].model.providerName // empty' "$PRD_FILE")
  SETTINGS_JSON=$(jq -c '[.userStories[] | select(.passes == false)] | sort_by(.priority) | .[0].model.settingsConfig // empty' "$PRD_FILE")

  # Clear log for this iteration (only keep current story's output)
  > "$OUTPUT_LOG"
  > "$OUTPUT_LOG.raw"

  # Display model info for this iteration
  if [ -n "$PROVIDER_NAME" ] && [ "$PROVIDER_NAME" != "null" ]; then
    echo "🤖 Model: $PROVIDER_NAME"
    echo "📖 Story: [$STORY_ID] $STORY_TITLE"
  else
    echo "🤖 Model: (default)"
    echo "📖 Story: [$STORY_ID] $STORY_TITLE"
  fi

  # Run the selected tool with the ralph prompt
  echo "🤖 Calling $TOOL..."
  echo "─────────────────────────────────────────────────────────────────"
  echo "💡 View live output in another terminal: tail -f $OUTPUT_LOG"
  echo ""

  # Disable set -e temporarily to capture output
  set +e

  if [[ "$TOOL" == "amp" ]]; then
    cat "$SCRIPT_DIR/prompt.md" | amp --dangerously-allow-all 2>&1 | tee "$OUTPUT_LOG"
    OUTPUT=$(cat "$OUTPUT_LOG")
  else
    CLAUDE_ARGS=(--dangerously-skip-permissions --print --output-format stream-json --verbose --include-partial-messages)
    if [ -n "$SETTINGS_JSON" ] && [ "$SETTINGS_JSON" != "null" ]; then
      CLAUDE_ARGS=(--settings "$SETTINGS_JSON" "${CLAUDE_ARGS[@]}")
    fi

    claude "${CLAUDE_ARGS[@]}" < "$SCRIPT_DIR/CLAUDE.md" 2>/dev/null \
      | tee "$OUTPUT_LOG.raw" \
      | jq --unbuffered -j '
        if .type == "stream_event" and .event.type == "content_block_delta" then
          .event.delta.text // empty
        elif .type == "assistant" and .error then
          "\n[ERROR] \(.message.content[0].text // .error)\n"
        elif .type == "result" then
          "\n[RESULT] stop_reason=\(.stop_reason) duration=\(.duration_ms)ms\n"
        else empty end
      ' \
      | awk -W interactive '
        BEGIN { empty = 0 }
        /^$/ {
          if (empty == 0) { print; empty = 1 }
          next
        }
        { print; empty = 0 }
      ' \
      > "$OUTPUT_LOG"

    OUTPUT=$(cat "$OUTPUT_LOG")
  fi

  set -e

  # Stop background status refresh
  cleanup_iter

  echo "─────────────────────────────────────────────────────────────────"

  # Check for completion signal
  if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
    echo ""
    echo "🎉 Ralph completed all tasks!"
    echo "✅ Completed at iteration $i of $MAX_ITERATIONS"
    exit 0
  fi

  echo ""
  echo "✅ Iteration $i complete"

  # Ask user before continuing (unless --no-prompt)
  if [ "$NO_PROMPT" = false ] && [ "$i" -lt "$MAX_ITERATIONS" ]; then
    echo ""
    read -p "❓ Continue to next iteration? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "🛑 Stopped by user after iteration $i"
      exit 1
    fi
  else
    echo "⏳ Waiting 2 seconds before next iteration..."
    sleep 2
  fi
done

echo ""
echo "⚠️ Ralph reached max iterations ($MAX_ITERATIONS) without completing all tasks."
echo "📝 Check $PROGRESS_FILE for status."
echo "💡 Tip: Run 'ralph' again to continue, or increase max iterations: 'ralph 20'"
exit 1
