#!/bin/bash
# Talkies hook — fired by Claude Code on Stop / Notification / AskUserQuestion.
# Reads the event JSON from stdin, extracts a summary of what Claude just did,
# and opens yap://record?summary=<text>&autosubmit=1 so Talkies shows the review
# card and automatically submits the reply when dictation finishes.

INPUT=$(cat)

EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // "Unknown"' 2>/dev/null || true)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null || true)

# --- Extract a summary for the review card ---

SUMMARY=""

if [ "$EVENT" = "PreToolUse" ]; then
  # AskUserQuestion: show the question text
  SUMMARY=$(echo "$INPUT" | jq -r '(.tool_input.questions // []) | first // ""' 2>/dev/null || true)
fi

# For Stop and Notification, read the last assistant message from the transcript JSONL.
if [ -z "$SUMMARY" ] && [ -f "$TRANSCRIPT" ]; then
  # Use slurp mode (-rs) so we get the entire 200-line window as an array, then find
  # the last assistant message that contains actual text (not just tool calls).
  # Handles both JSONL formats Claude Code uses:
  #   {"role":"assistant","content":[{"type":"text","text":"..."}]}
  #   {"type":"assistant","content":[{"type":"text","text":"..."}]}
  SUMMARY=$(tail -n 200 "$TRANSCRIPT" | jq -rs '
    [.[] |
      if (.role == "assistant" or .type == "assistant") then
        if (.content | type) == "array" then
          [.content[] | select(.type == "text") | .text] | join(" ")
        elif (.content | type) == "string" then .content
        else ""
        end
      else ""
      end
    ] | map(select(length > 0)) | last // ""
  ' 2>/dev/null || true)
fi

# Trim whitespace, collapse newlines, cap at 400 chars
SUMMARY=$(echo "$SUMMARY" | tr '\n' ' ' | sed 's/  */ /g; s/^[[:space:]]*//; s/[[:space:]]*$//' | cut -c1-400)

# URL-encode using python3 (standard on macOS)
if [ -n "$SUMMARY" ]; then
  ENCODED=$(python3 -c \
    "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" \
    "$SUMMARY" 2>/dev/null || printf '%s' "$SUMMARY" | jq -sRr @uri 2>/dev/null || true)
  open "yap://record?summary=$ENCODED&autosubmit=1"
else
  open "yap://record?autosubmit=1"
fi
