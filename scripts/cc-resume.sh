#!/bin/zsh
# Launch `claude --resume <sessionId>` with the minimal ACC env (same approach as
# cc-run-morning.sh — does NOT source all of ~/.zshrc, which broke model resolution).
# Called by the cc-web server inside a tmux session named "cc"; attach from Termius.
export PATH="/opt/homebrew/bin:/Users/calebweaver/.nvm/versions/node/v24.14.1/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export NODE_EXTRA_CA_CERTS="$HOME/bundle.pem"
eval "$(grep -m1 '^export FLOODGATE_PROJECT_TOKEN=' ~/.zshrc)"

id="$1"
cwd="$2"
cd "${cwd:-$HOME}" 2>/dev/null || cd "$HOME"
exec claude --resume "$id" --dangerously-skip-permissions
