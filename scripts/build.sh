#!/bin/zsh
# Build build/EXE.app from Sources/. Zero third-party dependencies.
set -euo pipefail
cd "${0:A:h}/.."
APP=build/EXE.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -swift-version 5 -O -target arm64-apple-macos14 \
  Sources/*.swift -o "$APP/Contents/MacOS/EXE" \
  -framework AppKit -framework WebKit -framework Carbon
cp Support/Info.plist "$APP/Contents/Info.plist"
cp -R web "$APP/Contents/Resources/web"
cp -R data "$APP/Contents/Resources/data"
codesign --force --sign - "$APP" >/dev/null
echo "built $APP"
