# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

A zero-dependency Claude Code hooks plugin that plays sound effects during Claude sessions. A single bash script (`hooks/claude-sounds.sh`) handles all events via Claude Code's hook system. No Node, Python, or external packages required beyond a system audio player.

## Install / Uninstall

```bash
./setup.sh      # install (copies hook script + sounds, merges settings.json)
./uninstall.sh  # remove everything (hook script, sounds dir, settings entries)
```

`setup.sh` requires `python3` or `jq` to merge `~/.claude/settings.json`. If neither is available, it prints the JSON to add manually.

## Testing the hook script manually

```bash
# Detect audio player
~/.claude/hooks/claude-sounds.sh detect-player

# Play a one-shot sound
echo '{}' | ~/.claude/hooks/claude-sounds.sh play success

# Test the thinking loop
echo '{"session_id":"test"}' | ~/.claude/hooks/claude-sounds.sh loop-start
sleep 3
echo '{"session_id":"test"}' | ~/.claude/hooks/claude-sounds.sh loop-stop
```

The script reads hook input JSON from stdin (Claude Code pipes it in automatically). Session isolation is done via `/tmp/claude-sounds-<session_id>.pid` files.

## Architecture

All logic lives in one file: `hooks/claude-sounds.sh`. It is a single-entry-point dispatcher with five subcommands:

| Subcommand | Hook event | Behavior |
|---|---|---|
| `loop-start` | `UserPromptSubmit` | Spawns background loop playing `thinking.mp3`; writes PID to `/tmp/claude-sounds-<session_id>.pid`; self-kills after 10 min watchdog |
| `loop-stop` | `Stop` | Kills loop process + child player via `pkill -P`; removes PID file |
| `session-end` | `SessionEnd` | Stops loop + kills any tracked one-shot PIDs |
| `play <name>` | `PostToolUse`, `PostToolUseFailure`, `Notification` | Plays one-shot sound in background; tracks PID in `/tmp/claude-sounds-oneshot-<session_id>.pids` |
| `detect-player` | — | Prints detected audio player or exits 1 |

**Player detection** checks `afplay → mpv → ffplay → paplay` in order. Volume flags differ per player; `build_play_cmd()` handles the translation.

**Sound file resolution**: `resolve_sound_file()` tries `.mp3` then `.wav` in `~/.claude/sounds/` (installed) or `../sounds/` (dev/repo).

**Environment variables** (set in shell profile):
- `CLAUDE_SOUNDS_VOLUME` — loop volume 0–100 (default: 30)
- `CLAUDE_SOUNDS_DISABLE` — comma-separated sound names to suppress (e.g. `success,notification`)

## Sound files

`sounds/` ships empty (`.gitkeep` only). Users add their own `thinking.mp3`, `success.mp3`, `failure.mp3`, `notification.mp3`. The `setup.sh` copies any files present in `sounds/` to `~/.claude/sounds/`.

## Stale PID cleanup

If the thinking loop doesn't stop, check `/tmp/claude-sounds-*.pid`. The `loop-start` command also kills any existing loop for the same session before starting a new one, handling interrupted sessions.
