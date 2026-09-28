#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
swift run --build-system native ClipHatChecks
BIN_DIR=$(swift build --build-system native --show-bin-path)
swiftc -I "$BIN_DIR/Modules" -I Sources/CSQLite \
  "$BIN_DIR"/ClipHatCore.build/*.o \
  Sources/ClipHat/Preferences.swift Sources/ClipHat/ClipboardStore.swift \
  Sources/ClipHat/ClipboardMonitor.swift Tests/MonitorChecks/main.swift \
  -o .build/ClipHatMonitorChecks
.build/ClipHatMonitorChecks
