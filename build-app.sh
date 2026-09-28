#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}"
cd "$ROOT"
swift build --build-system native -c release --product ClipHat
APP="$ROOT/ClipHat.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ClipHat "$APP/Contents/MacOS/ClipHat"
mkdir -p "$APP/Contents/Resources"
cp ClipHatIcon.png "$APP/Contents/Resources/ClipHatIcon.png"
cp ClipHatIcon.icns "$APP/Contents/Resources/ClipHatIcon.icns"
cp ClipHatMenuIcon.png "$APP/Contents/Resources/ClipHatMenuIcon.png"
cp MusicFilterIcon.png "$APP/Contents/Resources/MusicFilterIcon.png"
cp AppInfo.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
"$ROOT/../create-dmg-installer.sh" "$APP" "ClipHat" "$ROOT/ClipHat-1.0.2-install.dmg"
print "$APP"
