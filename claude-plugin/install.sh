#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR="$HOME/.config/yap/claude-hooks"
SETTINGS="$HOME/.claude/settings.json"

# Ensure jq is available
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required. Install it with: brew install jq" >&2
  exit 1
fi

# Install hook scripts
mkdir -p "$HOOKS_DIR"
cp "$SCRIPT_DIR/hooks/record.sh"  "$HOOKS_DIR/record.sh"
cp "$SCRIPT_DIR/hooks/dismiss.sh" "$HOOKS_DIR/dismiss.sh"
chmod +x "$HOOKS_DIR/record.sh" "$HOOKS_DIR/dismiss.sh"

# Create settings file if it doesn't exist
if [ ! -f "$SETTINGS" ]; then
  mkdir -p "$(dirname "$SETTINGS")"
  echo '{}' > "$SETTINGS"
fi

RECORD="$HOOKS_DIR/record.sh"
DISMISS="$HOOKS_DIR/dismiss.sh"

# Merge Talkies hooks into existing settings, appending to any existing hook arrays
UPDATED=$(jq \
  --arg record  "$RECORD" \
  --arg dismiss "$DISMISS" '
  .hooks //= {} |
  .hooks.Stop            //= [] |
  .hooks.Notification    //= [] |
  .hooks.PreToolUse      //= [] |
  .hooks.UserPromptSubmit //= [] |
  .hooks.Stop            += [{"hooks": [{"type": "command", "command": $record}]}] |
  .hooks.Notification    += [{"hooks": [{"type": "command", "command": $record}]}] |
  .hooks.PreToolUse      += [{"matcher": "AskUserQuestion", "hooks": [{"type": "command", "command": $record}]}] |
  .hooks.UserPromptSubmit += [{"hooks": [{"type": "command", "command": $dismiss}]}]
' "$SETTINGS")

echo "$UPDATED" > "$SETTINGS"
echo "Talkies hooks installed into $SETTINGS"
echo "Restart Claude Code for the changes to take effect."
