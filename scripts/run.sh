#!/bin/zsh
# Start (or restart) Vex. Logs -> logs/exe.log. Stop: ctrl+opt+cmd+Q, the menu-bar heart, or scripts/stop.sh
set -euo pipefail
cd "${0:A:h}/.."
[[ -x build/EXE.app/Contents/MacOS/EXE ]] || ./scripts/build.sh
python3 scripts/refresh_topics.py || echo "topic refresh failed; using existing topics.json"
./scripts/launch.sh
sleep 2
pgrep -f "EXE.app/Contents/MacOS/EXE" >/dev/null && echo "Vex is running. tail -f logs/exe.log" || { echo "Vex failed to start; see logs/exe.log"; exit 1; }
