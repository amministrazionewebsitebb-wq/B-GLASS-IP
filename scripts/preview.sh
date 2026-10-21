#!/bin/bash
# Renders the app's screens to PNG files with made-up data (macOS only, no Xcode needed).
#
#   scripts/preview.sh <output-dir> [scene ...]       scenes: welcome profiles home live guide movies series detail_movie
#                                                     detail_series search settings setup packs addlist pin network player
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${OUT:-${TMPDIR:-/tmp}/bglass-preview-build}"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
FLAGS=(-target arm64-apple-macos13.0 -sdk "$SDK" -D BGLASS_PLAIN_BUILD -Onone -enable-testing)
mkdir -p "$OUT"

swiftc "${FLAGS[@]}" -module-name BGlassCore -parse-as-library -emit-module -emit-module-path "$OUT/BGlassCore.swiftmodule" \
  -emit-library -static -o "$OUT/libBGlassCore.a" Sources/BGlassCore/*.swift 2>&1 | grep -E "error" -A3 || true
swiftc "${FLAGS[@]}" -I "$OUT" -module-name BGlassUI -parse-as-library -emit-module -emit-module-path "$OUT/BGlassUI.swiftmodule" \
  -emit-library -static -o "$OUT/libBGlassUI.a" Sources/BGlassUI/*.swift 2>&1 | grep -E "error" -A3 || true
swiftc "${FLAGS[@]}" -I "$OUT" -L "$OUT" -lBGlassUI -lBGlassCore -module-name BGlassPreview -parse-as-library \
  Sources/BGlassPreview/main.swift -o "$OUT/preview" 2>&1 | grep -E "error" -A3 || true

BGLASS_PACKS="$PWD/Sources/BGlassCore/Resources/packs.txt" "$OUT/preview" "$@"
