#!/bin/bash
# Compiles BGlassCore as a module and runs the self-checks on this Mac.
# Works with the command line tools only (no Xcode, no XCTest, no SwiftPM): plain swiftc.
#
#   scripts/check.sh            -> build + run the checks
#   OUT=/some/dir scripts/check.sh
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${OUT:-${TMPDIR:-/tmp}/bglass-check}"
mkdir -p "$OUT"

swiftc -Onone -module-name BGlassCore -parse-as-library -enable-testing -D BGLASS_PLAIN_BUILD \
  -emit-module -emit-module-path "$OUT/BGlassCore.swiftmodule" \
  -emit-library -static -o "$OUT/libBGlassCore.a" \
  Sources/BGlassCore/*.swift

swiftc -Onone -I "$OUT" -L "$OUT" -lBGlassCore -module-name BGlassChecks \
  Sources/BGlassChecks/*.swift -o "$OUT/bglass-checks"

BGLASS_PACKS="$PWD/Sources/BGlassCore/Resources/packs.txt" "$OUT/bglass-checks" "$@"
