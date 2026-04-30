#!/bin/bash
# Talkies hook — fired by Claude Code on Stop / Notification / AskUserQuestion.
# Reads the event JSON from stdin, extracts a summary of what Claude just did,
# and opens yap://record?summary=<text> so Talkies shows the review card.

set -euo pipefail

INPUT=$(cat)

EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // "Unknown"')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // ""')

# --- Extract a summary for the review card ---

SUMMARY=""

case "$EVENT" in
  "PreToolUse")
    # AskUserQuestion: the question text is the most useful summary
    SUMMARY=$(echo "$INPUT" | jq -r '
      (.tool_input.questions // []) | first // empty
    ' 2>/dev/null || true)
    ;;
esac

# For Stop and Notification (and any fallback), read the last assistant message
# from the transcript JSONL. Claude Code writes each turn as one JSON line.
if [ -z "$SUMMARY" ] && [ -f "$TRANSCRIPT" ]; then
  # Handle two JSONL formats Claude Code may use:
  #   {"role":"assistant","content":[{"type":"text","text":"..."}]}
  #   {"type":"assistant","message":{"content":[{"type":"text","text":"..."}]}}
  SUMMARY=$(tail -n 200 "$TRANSCRIPT" | jq -r '
    if .role == "assistant" then
      if (.content | type) == "array" then
        [.content[] | select(.type == "text") | .text] | join("")
      elif (.content | type) == "string" then .content
      else empty
      end
    elif .type == "assistant" then
      [(.message.content // [])[] | select(.type == "text") | .text] | join("")
    else empty
    end
  ' 2>/dev/null | grep -v '^$' | tail -1 || true)
fi

# Trim whitespace, collapse newlines, cap at 400 chars
SUMMARY=$(echo "$SUMMARY" | tr '\n' ' ' | sed 's/  */ /g' | sed 's/^ //; s/ $//' | cut -c1-400)

# URL-encode using python3 (standard on macOS)
if [ -n "$SUMMARY" ]; then
  ENCODED=$(python3 -c \
    "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" \
    "$SUMMARY" 2>/dev/null || printf '%s' "$SUMMARY" | jq -sRr @uri)
  open "yap://record?summary=$ENCODED"
else
  open "yap://record"
fi
