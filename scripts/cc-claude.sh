#!/bin/zsh
# Launch an interactive claude for the phone flow (fresh session) with the minimal ACC
# env and no mobile-hostile prompts (folder-trust / per-tool). Used as the default command
# of the "cc" tmux session so attaching lands you in Claude, not a bare shell.
export PATH="/opt/homebrew/bin:/Users/calebweaver/.nvm/versions/node/v24.14.1/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export NODE_EXTRA_CA_CERTS="$HOME/bundle.pem"
eval "$(grep -m1 '^export FLOODGATE_PROJECT_TOKEN=' ~/.zshrc)"
cd "$HOME"
# No arg to --resume => Claude Code's built-in interactive conversation picker.
exec claude --resume --dangerously-skip-permissions
