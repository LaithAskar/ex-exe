#!/bin/zsh
# Start Vex as a regular app (LaunchServices). Used by run.sh and the login LaunchAgent.
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p logs
pkill -f "EXE.app/Contents/MacOS/EXE" 2>/dev/null && sleep 1 || true
/usr/bin/open -n --env EXE_HOME="$PWD" --env PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" \
  --stdout "$PWD/logs/exe.log" --stderr "$PWD/logs/exe.log" build/EXE.app
