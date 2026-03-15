#!/usr/bin/env bash
# setup.sh — Installer for claude-sounds
# Copies hook script and sounds to ~/.claude, then merges hook config
# into ~/.claude/settings.json without overwriting existing settings.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

HOOKS_SRC="$SCRIPT_DIR/hooks/claude-sounds.sh"
SOUNDS_SRC="$SCRIPT_DIR/sounds"
HOOKS_DST="$HOME/.claude/hooks"
SOUNDS_DST="$HOME/.claude/sounds"
SETTINGS_FILE="$HOME/.claude/settings.json"
HOOK_SCRIPT="$HOOKS_DST/claude-sounds.sh"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info()    { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
success() { printf '\033[1;32m  ✓\033[0m %s\n' "$*"; }
warn()    { printf '\033[1;33m  !\033[0m %s\n' "$*" >&2; }
step()    { printf '\n\033[1;37m%s\033[0m\n' "$*"; }

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------

print_banner() {
  cat <<'EOF'

  ╔═══════════════════════════════════════════╗
  ║          claude-sounds installer          ║
  ║  Sound effects for Claude Code via hooks  ║
  ╚═══════════════════════════════════════════╝

  This will install:
    • ~/.claude/hooks/claude-sounds.sh   (hook script)
    • ~/.claude/sounds/                  (your sound files)
    • Hook entries in ~/.claude/settings.json

EOF
}

# ---------------------------------------------------------------------------
# Check for at least one audio player (warn only, don't fail)
# ---------------------------------------------------------------------------

check_audio_player() {
  step "Checking for audio player..."
  local found=""
  for player in afplay mpv ffplay paplay; do
    if command -v "$player" &>/dev/null; then
      found="$player"
      break
    fi
  done

  if [[ -n "$found" ]]; then
    success "Found audio player: $found"
  else
    warn "No audio player found (afplay / mpv / ffplay / paplay)."
    warn "Sounds will be silently skipped until you install one."
    warn "macOS: afplay is built-in."
    warn "Linux: sudo apt install mpv  OR  sudo dnf install mpv  OR  pacman -S mpv"
  fi
}

# ---------------------------------------------------------------------------
# Copy files
# ---------------------------------------------------------------------------

install_files() {
  step "Installing files..."

  mkdir -p "$HOOKS_DST"
  mkdir -p "$SOUNDS_DST"

  cp "$HOOKS_SRC" "$HOOK_SCRIPT"
  chmod +x "$HOOK_SCRIPT"
  success "Installed hook script → $HOOK_SCRIPT"

  # Copy any sound files that exist in the source directory
  local sound_count=0
  shopt -s nullglob
  for f in "$SOUNDS_SRC"/*.mp3 "$SOUNDS_SRC"/*.wav; do
    [[ -f "$f" ]] || continue
    cp "$f" "$SOUNDS_DST/"
    sound_count=$((sound_count + 1))
  done
  shopt -u nullglob

  if [[ "$sound_count" -gt 0 ]]; then
    success "Installed $sound_count sound file(s) → $SOUNDS_DST/"
  else
    warn "No sound files found in $SOUNDS_SRC/"
    warn "Add your own MP3/WAV files to $SOUNDS_DST/:"
    warn "  thinking.mp3   — looping background music while Claude thinks"
    warn "  success.mp3    — played after each successful tool call"
    warn "  failure.mp3    — played after a failed tool call"
    warn "  notification.mp3 — played when Claude needs your attention"
  fi
}

# ---------------------------------------------------------------------------
# JSON merging — inject hook entries into ~/.claude/settings.json
# Strategy: try Python3, then jq, then warn and show manual instructions.
# ---------------------------------------------------------------------------

# The hooks JSON block we want to merge in (as a shell variable for Python)
HOOKS_JSON='{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/claude-sounds.sh loop-start",
            "async": true,
            "timeout": 5
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/claude-sounds.sh play success",
            "async": true,
            "timeout": 5
          }
        ]
      }
    ],
    "PostToolUseFailure": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/claude-sounds.sh play failure",
            "async": true,
            "timeout": 5
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/claude-sounds.sh loop-stop",
            "async": true,
            "timeout": 5
          }
        ]
      }
    ],
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/claude-sounds.sh play notification",
            "async": true,
            "timeout": 5
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/claude-sounds.sh session-end",
            "async": true,
            "timeout": 5
          }
        ]
      }
    ]
  }
}'

merge_settings_python() {
  python3 - "$SETTINGS_FILE" <<'PYEOF'
import json, sys, os

settings_path = sys.argv[1]

new_hooks = {
    "UserPromptSubmit": [
        {"hooks": [{"type": "command", "command": "~/.claude/hooks/claude-sounds.sh loop-start", "async": True, "timeout": 5}]}
    ],
    "PostToolUse": [
        {"matcher": "", "hooks": [{"type": "command", "command": "~/.claude/hooks/claude-sounds.sh play success", "async": True, "timeout": 5}]}
    ],
    "PostToolUseFailure": [
        {"matcher": "", "hooks": [{"type": "command", "command": "~/.claude/hooks/claude-sounds.sh play failure", "async": True, "timeout": 5}]}
    ],
    "Stop": [
        {"hooks": [{"type": "command", "command": "~/.claude/hooks/claude-sounds.sh loop-stop", "async": True, "timeout": 5}]}
    ],
    "Notification": [
        {"hooks": [{"type": "command", "command": "~/.claude/hooks/claude-sounds.sh play notification", "async": True, "timeout": 5}]}
    ],
    "SessionEnd": [
        {"hooks": [{"type": "command", "command": "~/.claude/hooks/claude-sounds.sh session-end", "async": True, "timeout": 5}]}
    ],
}

# Load existing settings or start fresh
if os.path.exists(settings_path):
    with open(settings_path, "r") as f:
        try:
            settings = json.load(f)
        except json.JSONDecodeError:
            settings = {}
else:
    settings = {}

# Merge hooks: for each event type, append our entries if they're not already present
existing_hooks = settings.get("hooks", {})

def entry_already_present(existing_list, new_entry):
    """Check if a hook entry with the same command is already in the list."""
    new_cmds = {h.get("command") for h in new_entry.get("hooks", [])}
    for item in existing_list:
        existing_cmds = {h.get("command") for h in item.get("hooks", [])}
        if new_cmds & existing_cmds:
            return True
    return False

for event, entries in new_hooks.items():
    if event not in existing_hooks:
        existing_hooks[event] = entries
    else:
        for entry in entries:
            if not entry_already_present(existing_hooks[event], entry):
                existing_hooks[event].append(entry)

settings["hooks"] = existing_hooks

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")

print("ok")
PYEOF
}

merge_settings_jq() {
  local tmp
  tmp="$(mktemp)"

  # Build the new hooks JSON inline for jq
  jq --argjson new '{
    "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "~/.claude/hooks/claude-sounds.sh loop-start", "async": true, "timeout": 5}]}],
    "PostToolUse": [{"matcher": "", "hooks": [{"type": "command", "command": "~/.claude/hooks/claude-sounds.sh play success", "async": true, "timeout": 5}]}],
    "PostToolUseFailure": [{"matcher": "", "hooks": [{"type": "command", "command": "~/.claude/hooks/claude-sounds.sh play failure", "async": true, "timeout": 5}]}],
    "Stop": [{"hooks": [{"type": "command", "command": "~/.claude/hooks/claude-sounds.sh loop-stop", "async": true, "timeout": 5}]}],
    "Notification": [{"hooks": [{"type": "command", "command": "~/.claude/hooks/claude-sounds.sh play notification", "async": true, "timeout": 5}]}],
    "SessionEnd": [{"hooks": [{"type": "command", "command": "~/.claude/hooks/claude-sounds.sh session-end", "async": true, "timeout": 5}]}]
  }' \
  '. as $existing |
   reduce ($new | to_entries[]) as $e (
     $existing;
     .hooks[$e.key] = ((.hooks[$e.key] // []) + $e.value)
   )' \
  "$SETTINGS_FILE" > "$tmp"

  mv "$tmp" "$SETTINGS_FILE"
}

merge_settings() {
  step "Merging hook configuration into $SETTINGS_FILE..."

  # Ensure settings file exists
  if [[ ! -f "$SETTINGS_FILE" ]]; then
    echo '{}' > "$SETTINGS_FILE"
    success "Created $SETTINGS_FILE"
  fi

  # Try Python3 first (most reliable JSON merging)
  if command -v python3 &>/dev/null; then
    if merge_settings_python; then
      success "Merged hook config using Python3"
      return 0
    fi
    warn "Python3 merge failed, trying jq..."
  fi

  # Try jq
  if command -v jq &>/dev/null; then
    if merge_settings_jq; then
      success "Merged hook config using jq"
      return 0
    fi
    warn "jq merge failed."
  fi

  # Manual fallback — print instructions
  warn "Could not automatically merge settings (needs python3 or jq)."
  warn "Please manually add the following to $SETTINGS_FILE:"
  echo ""
  echo "$HOOKS_JSON"
  echo ""
}

# ---------------------------------------------------------------------------
# Offer a quick audio test
# ---------------------------------------------------------------------------

run_audio_test() {
  step "Quick audio test"
  printf 'Play each sound once to verify audio works? [y/N] '
  read -r answer
  case "$answer" in
    [yY]*)
      for sound in success failure notification; do
        info "Playing $sound..."
        echo '{}' | "$HOOK_SCRIPT" play "$sound" || true
        sleep 1
      done
      info "Playing thinking loop for 3 seconds..."
      echo '{"session_id":"setup-test"}' | "$HOOK_SCRIPT" loop-start || true
      sleep 3
      echo '{"session_id":"setup-test"}' | "$HOOK_SCRIPT" loop-stop || true
      success "Audio test complete"
      ;;
    *)
      info "Skipping audio test."
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Print summary
# ---------------------------------------------------------------------------

print_summary() {
  cat <<EOF

  ╔═══════════════════════════════════════════╗
  ║           Installation complete!          ║
  ╚═══════════════════════════════════════════╝

  Installed:
    $HOOK_SCRIPT
    $SOUNDS_DST/
    Hook entries in $SETTINGS_FILE

  Next steps:
    1. Add your sound files to $SOUNDS_DST/
       (thinking.mp3, success.mp3, failure.mp3, notification.mp3)
    2. Restart Claude Code — hooks take effect on next session
    3. Troubleshoot with: $HOOK_SCRIPT detect-player

  Customize via environment variables (in your shell profile):
    CLAUDE_SOUNDS_VOLUME=50         # Loop volume 0-100 (default: 50)
    CLAUDE_SOUNDS_DISABLE=success   # Comma-separated sounds to mute

  To uninstall: ./uninstall.sh

EOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

print_banner
check_audio_player
install_files
merge_settings
print_summary
run_audio_test
