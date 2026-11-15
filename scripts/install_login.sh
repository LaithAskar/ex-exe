#!/bin/zsh
# Launch Vex at login via a per-user LaunchAgent. Undo: scripts/uninstall_login.sh
# RunAtLoad only, no KeepAlive: if you quit her (ctrl+opt+cmd+Q) she stays quit until next login.
set -euo pipefail
cd "${0:A:h}/.."
ROOT="$PWD"
LABEL=com.laithaskar.exexe
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
[[ -x build/EXE.app/Contents/MacOS/EXE ]] || ./scripts/build.sh
mkdir -p logs "$HOME/Library/LaunchAgents"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$ROOT/build/EXE.app/Contents/MacOS/EXE</string></array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>EXE_HOME</key><string>$ROOT</string>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><false/>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardOutPath</key><string>$ROOT/logs/exe.log</string>
  <key>StandardErrorPath</key><string>$ROOT/logs/exe.log</string>
</dict>
</plist>
EOF
plutil -lint "$PLIST" >/dev/null

# Replace any manually-started instance with the launchd-managed one.
pkill -f "EXE.app/Contents/MacOS/EXE" 2>/dev/null || true
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "installed $PLIST - Vex now starts at login (and is running now)"
