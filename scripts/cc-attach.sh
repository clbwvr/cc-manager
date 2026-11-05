#!/bin/zsh
# Attach to (or create) a persistent tmux session named "cc" for interactive claude.
# Run from an iOS SSH client; the session survives phone disconnects so you can
# reconnect to the same claude conversation. Inside the session, just type: claude
export PATH="/opt/homebrew/bin:/Users/calebweaver/.nvm/versions/node/v24.14.1/bin:$PATH"
exec tmux new-session -A -s cc
