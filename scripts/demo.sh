#!/bin/zsh
# Start/stop the scripted demo (same as ctrl+opt+cmd+D). Tip: open YouTube first so the hide-app beat fires.
pkill -USR1 -f "EXE.app/Contents/MacOS/EXE" && echo "demo toggled" || echo "Vex is not running (scripts/run.sh)"
