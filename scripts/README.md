# Phone-side scripts

Helpers for using cc-manager / Claude Code from a phone over the home LAN. They are
expected to live in `~/bin` (the app and the Shortcuts invoke them by absolute path):

```
cp scripts/*.sh ~/bin/
mkdir -p ~/bin/cc-web && cp -r scripts/cc-web/* ~/bin/cc-web/
chmod +x ~/bin/cc-*.sh
```

| Script | Purpose |
| --- | --- |
| `cc-web/server.py` | Dependency-free web UI for browsing/searching/resuming conversations from a phone browser. Served at `http://<mac>.local:8787`. Started/stopped by cc-manager.app (see `WebServerController.swift`). |
| `cc-web.sh` | Launcher for the server (sets PATH, runs `server.py`). |
| `cc-attach.sh` | Attach to (or create) a persistent `tmux` session named `cc` for interactive `claude` from an SSH client (e.g. Termius). |
| `cc-resume.sh` | `claude --resume <id> [cwd]` with the minimal ACC env; invoked by the web UI's Resume button inside the `cc` tmux session. |
| `cc-run-morning.sh` | Headless `/morning` runner for the one-tap Shortcut; logs to `~/.claude/morning-runs/`. |

Notes:
- Paths (home dir, node version) are hard-coded for this machine.
- The ACC floodgate token is read from `~/.zshrc` at runtime — never stored here.
- Remote access is LAN-only by design (Apple InfoSec disallows third-party mesh VPNs).
