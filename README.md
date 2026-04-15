# cc-manager

Mac app for browsing, resuming, and forking Claude Code conversations.

## Build & run

```sh
cd ~/git/cc-manager
swift run -c release
```

To install as a `.app`-like launcher:

```sh
swift build -c release
cp .build/release/cc-manager /usr/local/bin/cc-manager
```

## Data

- Conversations: `~/.claude/projects/*/<session-id>.jsonl`
- User metadata (bases, custom titles): `~/.claude/cc-manager.json`

## Actions

- **Resume** — opens new iTerm2 window, `cd`s to original cwd, runs `claude --resume <id>`
- **Fork** — copies the JSONL to a new session id (rewrites the inner `sessionId` field), then resumes the new one
- **Rename** — stores a custom title in the sidecar metadata
- **Delete** — moves the JSONL to Trash
- **Toggle base (⭐)** — marks as a base conversation for easier forking
