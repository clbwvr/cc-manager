#!/bin/zsh
# Headless /morning runner, invoked over SSH from the phone.
#
# IMPORTANT: do NOT run this from inside an existing Claude Code session — a nested
# `claude` fights the parent over the ACC floodgate token and breaks both. It is
# meant to run as a standalone top-level process (e.g. an SSH command), with no
# other claude running.
#
# We set only the minimum ACC env (node on PATH, CA bundle, floodgate token) and
# deliberately do NOT `source ~/.zshrc` wholesale — doing so disturbed model
# resolution in testing.

export PATH="/Users/calebweaver/.nvm/versions/node/v24.14.1/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export NODE_EXTRA_CA_CERTS="$HOME/bundle.pem"
# Pull just the floodgate token line from ~/.zshrc without executing the rest.
eval "$(grep -m1 '^export FLOODGATE_PROJECT_TOKEN=' ~/.zshrc)"

cd "$HOME"
mkdir -p "$HOME/.claude/morning-runs"
ts="$(date +%Y-%m-%d_%H%M%S)"
LOG="$HOME/.claude/morning-runs/morning-$ts.log"

echo "[$ts] starting /morning" | tee "$LOG"
# --verbose streams tool activity so the log fills live instead of only at the end.
claude -p "/morning" --dangerously-skip-permissions --verbose 2>&1 | tee -a "$LOG"
echo "[$(date +%H%M%S)] done -> $LOG" | tee -a "$LOG"
