#!/bin/bash
set -e

SETTINGS="$HOME/.claude/settings.json"

# Ensure jq is available
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required. Install it with: brew install jq" >&2
  exit 1
fi

# Create settings file if it doesn't exist
if [ ! -f "$SETTINGS" ]; then
  mkdir -p "$(dirname "$SETTINGS")"
  echo '{}' > "$SETTINGS"
fi

# The hooks to add — all use the simple macOS open command to trigger the yap:// URL scheme
TALKIES_HOOKS=$(cat <<'EOF'
{
  "Stop": [{"hooks": [{"type": "command", "command": "open yap://record"}]}],
  "Notification": [{"hooks": [{"type": "command", "command": "open yap://record"}]}],
  "PreToolUse": [{"matcher": "AskUserQuestion", "hooks": [{"type": "command", "command": "open yap://record"}]}]
}
EOF
)

# Merge hooks into existing settings, appending to any existing hook arrays
UPDATED=$(jq --argjson new "$TALKIES_HOOKS" '
  .hooks //= {} |
  .hooks.Stop //= [] |
  .hooks.Notification //= [] |
  .hooks.PreToolUse //= [] |
  .hooks.Stop += $new.Stop |
  .hooks.Notification += $new.Notification |
  .hooks.PreToolUse += $new.PreToolUse
' "$SETTINGS")

echo "$UPDATED" > "$SETTINGS"
echo "Talkies hooks installed into $SETTINGS"
echo "Restart Claude Code for the changes to take effect."
