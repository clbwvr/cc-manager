# cc-manager

A native macOS app for browsing, searching, resuming, forking, and organizing
Claude Code conversations — plus a phone-accessible companion for using it from an
iPhone on the home LAN.

This README is written as a **regeneration spec**: if the source is lost, it carries
enough detail (architecture, data formats, decisions, and machine-specific facts) to
rebuild the whole system.

---

## 1. What it is

Claude Code stores every session as a JSONL transcript under `~/.claude/projects/`.
cc-manager is a SwiftUI desktop app that indexes those, and a small Python web server
(`cc-web`) that exposes the same data to a phone browser. Companion shell scripts let
you resume a conversation or run the `/morning` routine from the phone.

- **Language/stack:** Swift 5.9 + SwiftUI, macOS 14+, zero external Swift deps. Phone
  server is dependency-free Python 3 (stdlib only).
- **Bundle id:** `com.calebweaver.ccmanager`. Installed app: `~/Applications/cc-manager.app`.

## 2. Repo layout

```
Package.swift                      SwiftPM manifest (executable target "cc-manager")
install.sh                         Build release + assemble ~/Applications/cc-manager.app (icon via tools/make_icon.swift)
tools/make_icon.swift              Draws AppIcon.png -> .icns
Sources/CCManager/
  CCManagerApp.swift               @main; App scene + AppDelegate that starts/stops cc-web
  Models/
    Conversation.swift             Conversation + PreviewMessage (Codable)
    ConversationDragPayload.swift  Drag-and-drop payload for project assignment
  Services/
    ConversationStore.swift        @MainActor ObservableObject: scan, metadata, resume/fork/delete, deleteMany
    JSONLParser.swift              Parse a session .jsonl -> title/cwd/count/previews/searchableText (searchableCap=200_000)
    MetadataStore.swift            Load/save ~/.claude/cc-manager.json (titles, bases, projects, assignments)
    ParseCache.swift               Load/save ~/.claude/cc-manager-cache.json (parsed-session cache)
    SkillStore.swift               Slash commands for "new chat"
    WebServerController.swift      Launch/terminate the cc-web Python server as a child of the app
  Views/
    ContentView.swift              3-pane NavigationSplitView; toolbar (New Chat, Clean Up Old Chats)
    SidebarView.swift              Filters (All/Bases/Unassigned) + projects by status (active/todo/complete)
    ConversationListView.swift     Searchable list, context menu, keyboard shortcuts, multi-select delete
    ConversationDetailView.swift   Selected conversation preview + actions
    CleanupSheet.swift             Bulk-delete conversations older than a chosen age
    NewChatSheet / ProjectEditSheet / TextPromptSheet / MultiSelectionView
scripts/                           Phone-side helpers (install to ~/bin) — see scripts/README.md
  cc-web/server.py                 The phone web UI server
  cc-web/icon.png                  apple-touch-icon served at /icon.png
  cc-web.sh cc-attach.sh cc-resume.sh cc-run-morning.sh
```

## 3. Build / install / run

```sh
swift build -c release          # build
swift run -c release            # run from source
./install.sh                    # build + install ~/Applications/cc-manager.app (re-run after changes)
```

No test suite. No formatter configured.

## 4. Data model (files the system reads/writes)

- **Transcripts (read):** `~/.claude/projects/<slug>/<session-id>.jsonl`. One JSON object
  per line. Relevant line `type`s: `user`, `assistant` (with `message.content` as string
  or array of blocks; blocks with `type:"text"` carry text; `tool_result` blocks mark
  tool output), plus newer `ai-title` / `last-prompt` lines. `isSidechain:true` marks
  subagent lines (excluded from counts/preview). `cwd` is captured from the first line
  that has it. Files that parse to zero real messages and no title (e.g. `agent-*.jsonl`
  sidechains) are skipped.
- **User metadata (read/write):** `~/.claude/cc-manager.json` — `{ customTitles: {id:str},
  bases: [id], projects: [{id,name,description,knowledgeFiles,status}],
  conversationProjects: {id: projectId} }`. The transcripts themselves are never mutated
  except by Fork (which rewrites the inner `sessionId`).
- **Parse cache (read/write):** `~/.claude/cc-manager-cache.json` — `{ "<abs jsonl path>":
  { modified: <mtime epoch float>, size: <bytes>, cwd, firstUserMessage, messageCount,
  previews:[{role,text}], searchableText } }`. Entry is reused only if the file's current
  (mtime, size) match; otherwise re-parsed. Rebuilt wholesale each scan (stale entries drop).

## 5. App features

- Browse/search (title + path + full message content), newest first.
- **Resume** (desktop): opens a new iTerm2 tab, `cd` to cwd, `claude --resume <id>`.
- **Fork:** copy JSONL to a new UUID, rewrite inner `sessionId`, title "Fork of …".
- **Rename / Toggle base (⭐) / Move to project** via the sidecar metadata.
- **Delete / multi-delete:** move JSONL (and companion folder) to Trash; clean metadata.
- **Clean Up Old Chats** (`CleanupSheet`): pick an age threshold; lists everything older,
  oldest first; "Keep bases" + "Only unassigned" filters; per-item review; batch Trash via
  `ConversationStore.deleteMany` (single metadata save).
- **Performance:** `ParseCache` makes launches only re-parse changed files (cold ~0.8s of
  parsing → warm ~0.02s cache load). `searchableCap = 200_000` bounds per-session search
  text so memory and the cache file stay small.

## 6. Phone access (the companion system)

### Transport policy — READ THIS FIRST
This is an Apple corp-MDM-managed Mac. **Remote access runs over Tailscale** (installed,
IT-approved for this machine as of 2026-11-05). The Mac's tailnet address is
`calebs-macbook-pro-3.tail33f43d.ts.net` (`100.120.158.96`); the iPhone is on the same
tailnet. With Tailscale on, SSH and cc-web work from anywhere (verified; no `100.64.0.0/10`
conflict observed). Home-WiFi LAN (`.local`) still works as a fallback.

Caveat for anyone reusing this: Apple InfoSec's *general* stance (official #ask-infosec,
Oct 2026) is that third-party mesh VPNs (Tailscale/Headscale/NetBird) are **not** approved
([S.NTC.3]/[S.AUT.8]); the blanket-sanctioned remote paths are **SPVPN/Machine VPN or the
Admit gateway via GNS (`#help-vpn`)**. This setup rests on a specific IT exception, not the
general policy — confirm your own approval before installing a tunnel/overlay.

### Prereqs on the Mac
- System Settings → General → Sharing → **Remote Login** (SSH) on.
- SSH key `~/.ssh/cc_morning` (ed25519, no passphrase) with its pubkey in
  `~/.ssh/authorized_keys`. (Password auth also works as fallback.)
- `tmux` (via Homebrew) for persistent interactive sessions.
- Scripts installed to `~/bin` (see `scripts/README.md`).

### ACC environment (critical gotchas)
Claude Code here is **Apple Claude Code (ACC)** — it routes through a local proxy and needs:
- `NODE_EXTRA_CA_CERTS=$HOME/bundle.pem`
- `FLOODGATE_PROJECT_TOKEN` (exported in `~/.zshrc`; scripts read it at runtime via
  `eval "$(grep -m1 '^export FLOODGATE_PROJECT_TOKEN=' ~/.zshrc)"` — never hard-coded)
- node on PATH: `/Users/calebweaver/.nvm/versions/node/v24.14.1/bin` (+ `/opt/homebrew/bin` for tmux)

Two hard-won rules:
1. **One `claude` at a time.** The floodgate token is a single lease; a second concurrent
   `claude` makes *both* fail with `Invalid API key`. Never spawn a nested `claude` from
   inside a running Claude Code session.
2. **Do NOT `source ~/.zshrc` wholesale** in headless runners — it disturbed model
   resolution and produced `unrecognized_model` (e.g. `claude-sonnet-5-5[1m]`, "needs a
   newer version"). Set only the three env bits above. If an interactive run hits that
   error, launch with `claude --model <a supported model>`.

### Scripts (install to `~/bin`)
- **`cc-web/server.py`** — stdlib HTTP server, port **8787**, binds `0.0.0.0` (LAN).
  Endpoints: `GET /` (phone UI HTML), `GET /api/list?q=` (filtered list; search covers
  title+cwd+full content), `GET /api/detail?id=`, `POST /api/resume {id}`, `GET /icon.png`.
  Reads `~/.claude/projects` + `cc-manager.json` + the parse cache (falls back to a Python
  re-implementation of the parser for files not in cache). **Resume** does
  `tmux kill-session -t cc; tmux new-session -d -s cc "cc-resume.sh <id> <cwd>"`. Has a
  `watch_parent()` thread that exits the server if `CC_WEB_PARENT_PID` dies (ties it to the
  app). HTML includes `apple-mobile-web-app-capable` meta + `apple-touch-icon` so "Add to
  Home Screen" gives a fullscreen app tile.
- **`cc-web.sh`** — sets PATH, execs `python3 server.py`.
- **`cc-attach.sh`** — `exec tmux new-session -A -s cc` (attach-or-create the persistent
  "cc" session). Run this from the phone SSH client; type `claude` inside.
- **`cc-resume.sh <id> [cwd]`** — minimal ACC env, `cd`, `exec claude --resume <id>`.
- **`cc-run-morning.sh`** — minimal ACC env, `claude -p "/morning" --dangerously-skip-permissions
  --verbose`, logs to `~/.claude/morning-runs/`. For fire-and-forget triggering.

### Server lifecycle
`WebServerController` launches `~/bin/cc-web.sh` as a child of cc-manager.app on
`applicationDidFinishLaunching` (passing `CC_WEB_PARENT_PID`) and `terminate`s it on
`applicationWillTerminate`. **So the phone UI is up iff cc-manager is open.** No LaunchAgent.

### iOS setup
- **Interactive:** Termius (free). Host `calebs-macbook-pro-3.tail33f43d.ts.net` (Tailscale,
  works anywhere; on home WiFi `Calebs-MacBook-Pro.local` also works), user `calebweaver`,
  key `cc_morning`. Connect → `~/bin/cc-attach.sh` → `claude`. tmux keeps it alive across disconnects.
- **cc-manager UI:** Safari → `http://calebs-macbook-pro-3.tail33f43d.ts.net:8787` → Share →
  Add to Home Screen (opens fullscreen). Search → open conversation → copy the `claude --resume`
  command (long-press; clipboard API is unavailable over plain http) or tap Resume, then attach
  in Termius.
- **Morning:** Shortcut → Run Script Over SSH → `nohup ~/bin/cc-run-morning.sh >/dev/null 2>&1 </dev/null &`.

## 7. Machine-specific facts (for regeneration)
- User `calebweaver`, home `/Users/calebweaver`.
- Mac: `Calebs-MacBook-Pro.local`, LAN IP `192.168.1.158` (Verizon Fios router at
  `192.168.1.1`; **no UniFi gateway**, so UniFi Teleport is not an option).
- Tailscale (IT-approved): Mac `calebs-macbook-pro-3.tail33f43d.ts.net` / `100.120.158.96`;
  iPhone on the same tailnet. This is the anywhere-access transport.
- CA bundle: `~/bundle.pem`. node: `.nvm/.../v24.14.1`. tmux: `/opt/homebrew/bin/tmux`.
- cc-web port `8787`; tmux session name `cc`; SSH key `~/.ssh/cc_morning`.
