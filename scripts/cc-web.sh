#!/bin/zsh
# Start the cc-web server (phone UI for cc-manager). Reachable on the home LAN at
# http://Calebs-MacBook-Pro.local:8787 . tmux + claude are needed for Resume.
export PATH="/opt/homebrew/bin:/Users/calebweaver/.nvm/versions/node/v24.14.1/bin:/usr/bin:/bin:/usr/sbin:/sbin"
exec /usr/bin/python3 "$HOME/bin/cc-web/server.py"
