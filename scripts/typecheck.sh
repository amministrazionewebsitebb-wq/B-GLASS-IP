#!/bin/bash
# Type-checks the app code without Xcode.
#
#   1. BGlassCore + BGlassUI against the iOS API surface (Mac Catalyst target of the macOS SDK: UIKit, AVKit, WebKit...).
#   2. BGlassCore + BGlassUI against plain macOS (the SwiftUI screens are cross-platform; this is also what the preview tool uses).
#
# It does not link or run anything: it catches the errors a real iOS build would report in the Swift code.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${OUT:-${TMPDIR:-/tmp}/bglass-typecheck}"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p "$OUT/catalyst" "$OUT/macos"

FLAGS_CAT=(-target arm64-apple-ios16.0-macabi -sdk "$SDK" -F "$SDK/System/iOSSupport/System/Library/Frameworks" -D BGLASS_PLAIN_BUILD)
FLAGS_MAC=(-target arm64-apple-macos13.0 -sdk "$SDK" -D BGLASS_PLAIN_BUILD)

typecheck() { # name target-flags...
  local name="$1"; shift
  local dir="$OUT/$name"
  swiftc "$@" -module-name BGlassCore -parse-as-library -emit-module -emit-module-path "$dir/BGlassCore.swiftmodule" -o "$dir/core.o" -c Sources/BGlassCore/*.swift 2>&1 | grep -E "error" -A4 || true
  swiftc "$@" -I "$dir" -module-name BGlassUI -parse-as-library -typecheck Sources/BGlassUI/*.swift 2>&1 | grep -E "error" -A4 || true
}

echo "== iOS API surface (Mac Catalyst) =="
typecheck catalyst "${FLAGS_CAT[@]}"
if [ "${MACOS:-1}" = "1" ]; then
  echo "== macOS =="
  typecheck macos "${FLAGS_MAC[@]}"
fi
echo "done"
