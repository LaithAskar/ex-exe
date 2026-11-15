#!/bin/zsh
# Start (or restart) Vex. Uses the LaunchAgent if installed, otherwise a background process.
# Logs -> logs/exe.log. Stop: ctrl+opt+cmd+Q, the menu-bar heart, or scripts/stop.sh
set -euo pipefail
cd "${0:A:h}/.."
LABEL=com.laithaskar.exexe
[[ -x build/EXE.app/Contents/MacOS/EXE ]] || ./scripts/build.sh
python3 scripts/refresh_topics.py || echo "topic refresh failed; using existing topics.json"
mkdir -p logs
if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
  launchctl kickstart -k "gui/$(id -u)/$LABEL"
  echo "Vex (re)started via launchd. tail -f logs/exe.log"
else
  ./scripts/stop.sh >/dev/null 2>&1 || true
  EXE_HOME="$PWD" nohup build/EXE.app/Contents/MacOS/EXE >> logs/exe.log 2>&1 &
  echo "Vex is running (pid $!). tail -f logs/exe.log"
fi
