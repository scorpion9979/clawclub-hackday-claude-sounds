#!/usr/bin/env bash
# uninstall.sh — Remove claude-sounds from ~/.claude
# Removes hook script, sounds directory, and hook entries from settings.json.
# Does NOT remove other hooks or settings.
set -euo pipefail

HOOKS_DST="$HOME/.claude/hooks/claude-sounds.sh"
SOUNDS_DST="$HOME/.claude/sounds"
SETTINGS_FILE="$HOME/.claude/settings.json"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info()    { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
success() { printf '\033[1;32m  ✓\033[0m %s\n' "$*"; }
warn()    { printf '\033[1;33m  !\033[0m %s\n' "$*" >&2; }
step()    { printf '\n\033[1;37m%s\033[0m\n' "$*"; }

# ---------------------------------------------------------------------------
# Kill any running thinking loops
# ---------------------------------------------------------------------------

kill_running_loops() {
  step "Stopping any running thinking loops..."
  local killed=0
  for pid_file in /tmp/claude-sounds-*.pid; do
    [[ -f "$pid_file" ]] || continue
    local pid
    pid="$(cat "$pid_file")"
    if kill -0 "$pid" 2>/dev/null; then
      kill -- -"$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
      success "Killed loop PID $pid (from $pid_file)"
      killed=$((killed + 1))
    fi
    rm -f "$pid_file"
  done
  if [[ "$killed" -eq 0 ]]; then
    info "No running loops found."
  fi
}

# ---------------------------------------------------------------------------
# Remove installed files
# ---------------------------------------------------------------------------

remove_files() {
  step "Removing installed files..."

  if [[ -f "$HOOKS_DST" ]]; then
    rm -f "$HOOKS_DST"
    success "Removed $HOOKS_DST"
  else
    info "Hook script not found (already removed?): $HOOKS_DST"
  fi

  if [[ -d "$SOUNDS_DST" ]]; then
    rm -rf "$SOUNDS_DST"
    success "Removed $SOUNDS_DST"
  else
    info "Sounds directory not found (already removed?): $SOUNDS_DST"
  fi
}

# ---------------------------------------------------------------------------
# Remove claude-sounds entries from settings.json.
# Uses Python3 or jq — same strategy as setup.sh.
# ---------------------------------------------------------------------------

CLAUDE_SOUNDS_COMMANDS=(
  "~/.claude/hooks/claude-sounds.sh loop-start"
  "~/.claude/hooks/claude-sounds.sh loop-stop"
  "~/.claude/hooks/claude-sounds.sh play success"
  "~/.claude/hooks/claude-sounds.sh play failure"
  "~/.claude/hooks/claude-sounds.sh play notification"
)

remove_settings_python() {
  python3 - "$SETTINGS_FILE" <<'PYEOF'
import json, sys, os

settings_path = sys.argv[1]

# Commands that identify claude-sounds hooks
sounds_commands = {
    "~/.claude/hooks/claude-sounds.sh loop-start",
    "~/.claude/hooks/claude-sounds.sh loop-stop",
    "~/.claude/hooks/claude-sounds.sh play success",
    "~/.claude/hooks/claude-sounds.sh play failure",
    "~/.claude/hooks/claude-sounds.sh play notification",
}

if not os.path.exists(settings_path):
    sys.exit(0)

with open(settings_path, "r") as f:
    try:
        settings = json.load(f)
    except json.JSONDecodeError:
        sys.exit(0)

if "hooks" not in settings:
    sys.exit(0)

def is_sounds_entry(entry):
    """Return True if all hooks in this entry are claude-sounds commands."""
    hooks = entry.get("hooks", [])
    return all(h.get("command") in sounds_commands for h in hooks) and len(hooks) > 0

cleaned_hooks = {}
for event, entries in settings["hooks"].items():
    remaining = [e for e in entries if not is_sounds_entry(e)]
    if remaining:
        cleaned_hooks[event] = remaining
    # If all entries were claude-sounds, drop the event key entirely

settings["hooks"] = cleaned_hooks

# Remove the hooks key entirely if empty
if not settings["hooks"]:
    del settings["hooks"]

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")

print("ok")
PYEOF
}

remove_settings_jq() {
  local tmp
  tmp="$(mktemp)"

  # Build a jq filter that removes entries whose hooks are all claude-sounds commands
  jq 'if .hooks then
    .hooks |= with_entries(
      .value |= map(
        select(
          .hooks | all(
            .command | IN(
              "~/.claude/hooks/claude-sounds.sh loop-start",
              "~/.claude/hooks/claude-sounds.sh loop-stop",
              "~/.claude/hooks/claude-sounds.sh play success",
              "~/.claude/hooks/claude-sounds.sh play failure",
              "~/.claude/hooks/claude-sounds.sh play notification"
            )
          ) | not
        )
      )
    ) |
    with_entries(select(.value | length > 0))
  else . end |
  if (.hooks // {}) == {} then del(.hooks) else . end' \
  "$SETTINGS_FILE" > "$tmp"

  mv "$tmp" "$SETTINGS_FILE"
}

remove_settings() {
  step "Removing hook entries from $SETTINGS_FILE..."

  if [[ ! -f "$SETTINGS_FILE" ]]; then
    info "Settings file not found: $SETTINGS_FILE"
    return 0
  fi

  if command -v python3 &>/dev/null; then
    if remove_settings_python; then
      success "Removed hook entries using Python3"
      return 0
    fi
    warn "Python3 removal failed, trying jq..."
  fi

  if command -v jq &>/dev/null; then
    if remove_settings_jq; then
      success "Removed hook entries using jq"
      return 0
    fi
    warn "jq removal failed."
  fi

  warn "Could not automatically remove hook entries from $SETTINGS_FILE."
  warn "Please manually remove any entries referencing 'claude-sounds.sh' from that file."
}

# ---------------------------------------------------------------------------
# Print summary
# ---------------------------------------------------------------------------

print_summary() {
  cat <<'EOF'

  ╔═══════════════════════════════════════════╗
  ║         Uninstall complete!               ║
  ╚═══════════════════════════════════════════╝

  claude-sounds has been removed.
  Restart Claude Code to apply the changes.

EOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

echo ""
echo "Uninstalling claude-sounds..."

kill_running_loops
remove_files
remove_settings
print_summary
