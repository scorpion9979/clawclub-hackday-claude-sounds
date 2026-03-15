#!/usr/bin/env bash
# claude-sounds.sh — Sound effects system for Claude Code hooks
# Single entry-point script with five subcommands:
#   loop-start   — start looping the thinking music (called on UserPromptSubmit)
#   loop-stop    — stop the thinking music loop (called on Stop)
#   session-end  — stop loop + all one-shot sounds for the session (called on SessionEnd)
#   play <name>  — play a one-shot sound (success/failure/notification)
#   detect-player — print the detected audio player name
set -euo pipefail

# ---------------------------------------------------------------------------
# Path resolution — works both in dev (relative) and installed (~/.claude)
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Prefer installed sounds dir, fall back to dev path relative to hooks/
if [[ -d "$HOME/.claude/sounds" ]]; then
  SOUNDS_DIR="$HOME/.claude/sounds"
else
  SOUNDS_DIR="$SCRIPT_DIR/../sounds"
fi

PID_DIR="/tmp"

# ---------------------------------------------------------------------------
# Volume configuration via environment variables
#   CLAUDE_SOUNDS_VOLUME    — 0-100, volume for thinking loop (default 50)
#   CLAUDE_SOUNDS_DISABLE   — comma-separated list of sounds to suppress
#                             e.g. "success,notification"
# ---------------------------------------------------------------------------

LOOP_VOLUME="${CLAUDE_SOUNDS_VOLUME:-50}"
ONESHOT_VOLUME=100

# Check if a sound name is disabled via CLAUDE_SOUNDS_DISABLE env var
sound_is_disabled() {
  local name="$1"
  local disable_list="${CLAUDE_SOUNDS_DISABLE:-}"
  [[ -n "$disable_list" ]] && echo "$disable_list" | tr ',' '\n' | grep -qx "$name"
}

# ---------------------------------------------------------------------------
# Audio player detection — checks for players in preference order and caches
# the result in DETECTED_PLAYER. Returns 1 (silently) if none found.
# ---------------------------------------------------------------------------

DETECTED_PLAYER=""

detect_player() {
  # Return cached result if already detected
  [[ -n "$DETECTED_PLAYER" ]] && return 0

  for player in afplay mpv ffplay paplay; do
    if command -v "$player" &>/dev/null; then
      DETECTED_PLAYER="$player"
      return 0
    fi
  done

  # No player found — all audio commands will be no-ops
  DETECTED_PLAYER=""
  return 1
}

# ---------------------------------------------------------------------------
# Build the play command string for a given file and mode.
# mode: "oneshot" | "loop"
# Prints the full command to stdout for use with eval.
# ---------------------------------------------------------------------------

build_play_cmd() {
  local player="$1"
  local file="$2"
  local mode="$3"  # "oneshot" or "loop"

  local vol_arg=""
  if [[ "$mode" == "loop" ]]; then
    local vol="$LOOP_VOLUME"
    case "$player" in
      afplay)  vol_arg="--volume $(awk "BEGIN{printf \"%.2f\",$vol/100}")";;
      mpv)     vol_arg="--volume=$vol";;
      ffplay)  vol_arg="-volume $vol";;
      paplay)  vol_arg="--volume=32768";;  # paplay uses raw PCM scale; 32768 ≈ 50%
    esac
  fi

  case "$player" in
    afplay)
      echo "afplay ${vol_arg} \"${file}\""
      ;;
    mpv)
      echo "mpv --no-terminal ${vol_arg} \"${file}\""
      ;;
    ffplay)
      echo "ffplay -nodisp -autoexit ${vol_arg} \"${file}\""
      ;;
    paplay)
      echo "paplay ${vol_arg} \"${file}\""
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Resolve sound file path — try .mp3 first, fall back to .wav
# Prints the resolved path, or returns 1 if neither exists.
# ---------------------------------------------------------------------------

resolve_sound_file() {
  local name="$1"
  local mp3="$SOUNDS_DIR/${name}.mp3"
  local wav="$SOUNDS_DIR/${name}.wav"

  if [[ -f "$mp3" ]]; then
    echo "$mp3"
  elif [[ -f "$wav" ]]; then
    echo "$wav"
  else
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Parse session_id from JSON on stdin.
# Uses lightweight grep/cut — no jq dependency.
# Falls back to "default" if parsing fails.
# ---------------------------------------------------------------------------

parse_session_id() {
  local raw
  # Read all of stdin first to avoid broken pipe errors downstream
  raw="$(cat -)"
  local sid
  sid="$(printf '%s' "$raw" | grep -o '"session_id":"[^"]*"' | cut -d'"' -f4 || true)"
  if [[ -z "$sid" ]]; then
    sid="default"
  fi
  echo "$sid"
}

# ---------------------------------------------------------------------------
# cmd_detect_player — print detected player or a warning to stderr
# ---------------------------------------------------------------------------

cmd_detect_player() {
  if detect_player; then
    echo "$DETECTED_PLAYER"
  else
    echo "No audio player found. Install afplay (macOS built-in), mpv, ffplay, or paplay." >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# cmd_loop_start — start the thinking music loop in the background.
# Reads JSON from stdin to extract session_id.
# Writes the loop PID to /tmp/claude-sounds-<session_id>.pid.
# Self-terminates after 10 minutes via a watchdog subshell.
# ---------------------------------------------------------------------------

cmd_loop_start() {
  local session_id
  session_id="$(parse_session_id)"

  local pid_file="${PID_DIR}/claude-sounds-${session_id}.pid"

  # Clean up stale PID file if the process is already dead
  if [[ -f "$pid_file" ]]; then
    local old_pid
    old_pid="$(cat "$pid_file")"
    if ! kill -0 "$old_pid" 2>/dev/null; then
      rm -f "$pid_file"
    else
      # Loop already running for this session — nothing to do
      exit 0
    fi
  fi

  # No audio player — exit silently
  if ! detect_player; then
    exit 0
  fi

  local sound_file
  if ! sound_file="$(resolve_sound_file "thinking")"; then
    # No thinking sound file — exit silently
    exit 0
  fi

  if sound_is_disabled "thinking"; then
    exit 0
  fi

  local play_cmd
  play_cmd="$(build_play_cmd "$DETECTED_PLAYER" "$sound_file" "loop")"

  # Spawn the loop in a background subshell (new process group via setsid/nohup)
  # The 0.5s gap between iterations prevents audio stutter on seamless looping.
  (
    while true; do
      eval "$play_cmd" &>/dev/null || true
      sleep 0.5
    done
  ) &

  local loop_pid=$!
  echo "$loop_pid" > "$pid_file"

  # Watchdog: kill the loop after 10 minutes as a safety net
  (
    sleep 600
    if [[ -f "$pid_file" ]]; then
      local current_pid
      current_pid="$(cat "$pid_file" 2>/dev/null || echo "")"
      if [[ "$current_pid" == "$loop_pid" ]]; then
        kill -- -"$loop_pid" 2>/dev/null || kill "$loop_pid" 2>/dev/null || true
        rm -f "$pid_file"
      fi
    fi
  ) &

  # Disown watchdog so it survives the parent exiting
  disown $! 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# cmd_loop_stop — stop the thinking music loop for a session.
# Reads JSON from stdin to extract session_id.
# No-op if PID file is missing or process is already dead.
# ---------------------------------------------------------------------------

cmd_loop_stop() {
  local session_id
  session_id="$(parse_session_id)"

  local pid_file="${PID_DIR}/claude-sounds-${session_id}.pid"

  # Nothing to stop if no PID file
  [[ -f "$pid_file" ]] || exit 0

  local pid
  pid="$(cat "$pid_file")"

  # Try to kill the process group (kills both loop shell and child player)
  if kill -0 "$pid" 2>/dev/null; then
    kill -- -"$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
  fi

  rm -f "$pid_file"
  exit 0
}

# ---------------------------------------------------------------------------
# cmd_play <sound> — play a one-shot sound in the background.
# Reads JSON from stdin to extract session_id for cleanup tracking.
# Exits immediately without waiting for playback to finish.
# ---------------------------------------------------------------------------

cmd_play() {
  local sound_name="$1"
  local session_id
  session_id="$(parse_session_id)"

  if sound_is_disabled "$sound_name"; then
    exit 0
  fi

  # No audio player — exit silently
  if ! detect_player; then
    exit 0
  fi

  local sound_file
  if ! sound_file="$(resolve_sound_file "$sound_name")"; then
    # No sound file for this name — warn on stderr but don't fail the hook
    echo "claude-sounds: no sound file found for '${sound_name}' in ${SOUNDS_DIR}" >&2
    exit 0
  fi

  local play_cmd
  play_cmd="$(build_play_cmd "$DETECTED_PLAYER" "$sound_file" "oneshot")"

  # Fire and forget — run in background, track PID for session cleanup
  eval "$play_cmd" &>/dev/null &
  local play_pid=$!
  echo "$play_pid" >> "${PID_DIR}/claude-sounds-oneshot-${session_id}.pids"
  disown "$play_pid" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# cmd_session_end — stop all sounds for a session (loop + one-shot).
# Reads JSON from stdin to extract session_id.
# Called on SessionEnd to ensure clean teardown when the user exits.
# ---------------------------------------------------------------------------

cmd_session_end() {
  local session_id
  session_id="$(parse_session_id)"

  # Stop the thinking loop
  local pid_file="${PID_DIR}/claude-sounds-${session_id}.pid"
  if [[ -f "$pid_file" ]]; then
    local pid
    pid="$(cat "$pid_file")"
    if kill -0 "$pid" 2>/dev/null; then
      kill -- -"$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
    fi
    rm -f "$pid_file"
  fi

  # Kill any tracked one-shot sounds still running
  local oneshot_file="${PID_DIR}/claude-sounds-oneshot-${session_id}.pids"
  if [[ -f "$oneshot_file" ]]; then
    while IFS= read -r pid; do
      [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
    done < "$oneshot_file"
    rm -f "$oneshot_file"
  fi

  exit 0
}

# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------

SUBCOMMAND="${1:-}"

case "$SUBCOMMAND" in
  loop-start)
    cmd_loop_start
    ;;
  loop-stop)
    cmd_loop_stop
    ;;
  session-end)
    cmd_session_end
    ;;
  play)
    if [[ -z "${2:-}" ]]; then
      echo "Usage: claude-sounds.sh play <sound-name>" >&2
      exit 1
    fi
    cmd_play "$2"
    ;;
  detect-player)
    cmd_detect_player
    ;;
  "")
    echo "Usage: claude-sounds.sh <loop-start|loop-stop|session-end|play <sound>|detect-player>" >&2
    exit 1
    ;;
  *)
    echo "Unknown subcommand: $SUBCOMMAND" >&2
    echo "Usage: claude-sounds.sh <loop-start|loop-stop|session-end|play <sound>|detect-player>" >&2
    exit 1
    ;;
esac
