#!/bin/zsh
# Attach to (or create) the persistent "cc" tmux session. If it has to create the session
# it starts claude (via cc-claude.sh), so attaching lands you in Claude, not a bare shell.
# If the session already exists (e.g. a cc-web Resume populated it), you attach to that.
export PATH="/opt/homebrew/bin:/Users/calebweaver/.nvm/versions/node/v24.14.1/bin:$PATH"
exec tmux new-session -A -s cc "$HOME/bin/cc-claude.sh"
