# Notchi

A macOS notch companion that reacts to Claude Code activity in real-time.

<video src="assets/demo.mp4" controls autoplay muted loop width="600"></video>

## What it does

- Reacts to Claude Code events in real-time (thinking, working, errors, completions)
- Analyzes conversation sentiment to show emotions (happy, sad, neutral, sob)
- Click to expand and see session usage
- Supports multiple concurrent Claude Code sessions with individual sprites
- Sound effects for events (optional, auto-muted when terminal is focused)
- Auto-updates via Sparkle

## Install

1. Download `Notchi-x.x.x.dmg` from the [latest GitHub Release](https://github.com/sk-ruban/notchi/releases/latest)
2. Open the DMG and drag Notchi to Applications
3. Launch Notchi — it auto-installs Claude Code hooks on first launch
4. A macOS keychain popup will appear asking to access Claude Code's cached OAuth token (used for API usage stats). Click **Always Allow** so it won't prompt again on future launches

   <img src="assets/keychain-popup.png" alt="Keychain access popup" width="450">

5. *(Optional)* Click the notch to expand → open Settings → paste your Anthropic API key. This enables sentiment analysis of your prompts so the mascot reacts emotionally

   <img src="assets/emotion-settings.png" alt="Emotion analysis settings" width="400">

6. Start using Claude Code and watch Notchi react

## Requirements

- macOS 15.0+ (Sequoia)
- MacBook with notch
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed

## How it works

```
Claude Code --> Hooks (shell scripts) --> Unix Socket --> Event Parser --> State Machine --> Animated Sprites
```

Notchi registers shell script hooks with Claude Code on launch. When Claude Code emits events (tool use, thinking, prompts, session start/end), the hook script sends JSON payloads to a Unix socket. The app parses these events, runs them through a state machine that maps to sprite animations (idle, working, sleeping, compacting, waiting), and uses the Anthropic API to analyze user prompt sentiment for emotional reactions.

Each Claude Code session gets its own sprite on the grass island. Clicking expands the notch panel to show a live activity feed, session info, and API usage stats.

## License

MIT
