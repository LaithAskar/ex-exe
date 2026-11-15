#!/bin/zsh
set -uo pipefail
LABEL=com.laithaskar.exexe
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
echo "Vex will no longer start at login."
