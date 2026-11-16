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
  <!-- Launch through LaunchServices ("open"), not the bare binary: a bare-exec'd app's windows are skipped by
       macOS screen *recording* (ScreenCaptureKit), so Vex would vanish from demo videos. -->
  <key>ProgramArguments</key><array><string>$ROOT/scripts/launch.sh</string></array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>EXE_HOME</key><string>$ROOT</string>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><false/>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
  <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
EOF
plutil -lint "$PLIST" >/dev/null

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"   # RunAtLoad -> launch.sh (restarts her if already running)
echo "installed $PLIST - Vex now starts at login (and is running now)"
