# claude-sounds

> Zero-dependency sound effects for Claude Code, powered entirely by hooks.

Plays Elevator Music while Claude is thinking, Vine Boom on tool success, Fahhh on errors, and Bruh when Claude needs your attention.

---

## How it works

| Hook event | Sound file | Behavior |
|---|---|---|
| `UserPromptSubmit` | `thinking.mp3` | Loops Elevator Music while Claude works |
| `Stop` | _(none)_ | Stops the thinking loop |
| `PostToolUse` | `success.mp3` | One-shot Vine Boom after each successful tool call |
| `PostToolUseFailure` | `failure.mp3` | One-shot Fahhh after a failed tool call |
| `Notification` | `notification.mp3` | One-shot Bruh when Claude needs your attention |

A single bash script (`claude-sounds.sh`) handles all events. It auto-detects your system audio player and resolves sound files relative to `~/.claude/sounds/`. No Node, no Python, no external packages.

---

## Prerequisites

At least one of:

| Platform | Player | Install |
|---|---|---|
| macOS | `afplay` | Built-in (no action needed) |
| Ubuntu / Debian | `mpv` | `sudo apt install mpv` |
| Fedora / RHEL | `mpv` | `sudo dnf install mpv` |
| Arch Linux | `mpv` | `sudo pacman -S mpv` |
| Any Linux | `ffplay` | `sudo apt install ffmpeg` |
| Any Linux | `paplay` | Included with PulseAudio |

---

## Quick install

```bash
git clone https://github.com/yourname/claude-sounds
cd claude-sounds
./setup.sh
```

Then restart Claude Code. The hooks take effect on the next session.

**Add your sound files** to `~/.claude/sounds/`:

```
~/.claude/sounds/
├── thinking.mp3      # Elevator Music — looping (10+ sec recommended for seamless looping)
├── success.mp3       # Vine Boom (< 1 sec)
├── failure.mp3       # Fahhh (< 1 sec)
└── notification.mp3  # Bruh (< 1 sec)
```

MP3 and WAV formats are both supported. MP3 is tried first; WAV is used as fallback.

---

## Manual install

If you prefer to install manually without `setup.sh`:

```bash
# 1. Copy the hook script
mkdir -p ~/.claude/hooks
cp hooks/claude-sounds.sh ~/.claude/hooks/claude-sounds.sh
chmod +x ~/.claude/hooks/claude-sounds.sh

# 2. Create sounds directory and add your files
mkdir -p ~/.claude/sounds
# cp your-sounds/*.mp3 ~/.claude/sounds/

# 3. Merge hook config into ~/.claude/settings.json
#    (add the JSON from the Hook Configuration section below)
```

### Hook configuration

Add this to `~/.claude/settings.json` (merge into any existing `hooks` key):

```json
{
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
    ]
  }
}
```

---

## Customizing sounds

Swap any file in `~/.claude/sounds/` with your own:

```bash
cp my-chime.mp3 ~/.claude/sounds/success.mp3
cp my-music.mp3 ~/.claude/sounds/thinking.mp3
```

No restart needed — the hook script reads files at play time.

**Recommended sources for free sounds:**
- [freesound.org](https://freesound.org) — Creative Commons licensed
- [mixkit.co](https://mixkit.co/free-sound-effects/) — Free for personal use
- [pixabay.com/sound-effects](https://pixabay.com/sound-effects/) — Royalty-free

---

## Adjusting volume

Set `CLAUDE_SOUNDS_VOLUME` in your shell profile (`~/.zshrc`, `~/.bashrc`, etc.):

```bash
# Thinking loop volume: 0–100 (default: 50)
export CLAUDE_SOUNDS_VOLUME=30
```

One-shot sounds (success, failure, notification) always play at full volume.

---

## Disabling specific sounds

Set `CLAUDE_SOUNDS_DISABLE` to a comma-separated list of sound names:

```bash
# Disable only the success sound
export CLAUDE_SOUNDS_DISABLE=success

# Disable multiple sounds
export CLAUDE_SOUNDS_DISABLE=success,notification

# Disable all sounds (but keep hooks registered)
export CLAUDE_SOUNDS_DISABLE=thinking,success,failure,notification
```

---

## Uninstall

```bash
./uninstall.sh
```

This removes:
- `~/.claude/hooks/claude-sounds.sh`
- `~/.claude/sounds/`
- claude-sounds hook entries from `~/.claude/settings.json`
- Any running thinking loops

Other hooks and settings are left untouched.

---

## Troubleshooting

### No sound plays

1. Check player detection:
   ```bash
   ~/.claude/hooks/claude-sounds.sh detect-player
   ```
   If this prints nothing or errors, install a supported audio player (see Prerequisites).

2. Check that sound files exist:
   ```bash
   ls ~/.claude/sounds/
   ```
   The `sounds/` directory ships empty. You must add your own MP3/WAV files.

3. Test a one-shot manually:
   ```bash
   echo '{}' | ~/.claude/hooks/claude-sounds.sh play success
   ```

4. Test the loop manually:
   ```bash
   echo '{"session_id":"test"}' | ~/.claude/hooks/claude-sounds.sh loop-start
   sleep 5
   echo '{"session_id":"test"}' | ~/.claude/hooks/claude-sounds.sh loop-stop
   ```

### Thinking music doesn't stop

Check for stale PID files:
```bash
ls /tmp/claude-sounds-*.pid
```

Kill any orphaned loop:
```bash
cat /tmp/claude-sounds-test.pid | xargs kill 2>/dev/null || true
rm /tmp/claude-sounds-*.pid
```

The loop also self-terminates after 10 minutes as a safety net.

### Settings merge failed during setup

Run setup with Python or jq available:
```bash
which python3   # preferred
which jq        # fallback
```

Or manually add the hook configuration JSON (see Manual install section above) to `~/.claude/settings.json`.

---

## Security note

The hook script runs with your user permissions. You can audit what it does in ~5 minutes by reading `hooks/claude-sounds.sh` — it's a single self-contained file with no network calls, no external dependencies beyond a system audio player.
