#!/bin/bash
# Builds an unsigned BGlass.ipa (to be signed and installed with Sideloadly / AltStore using your own Apple ID).
#
#   scripts/build_ipa.sh              with VLC (plays MKV and raw MPEG-TS too)
#   scripts/build_ipa.sh --no-vlc     AVPlayer only (smaller; HLS and MP4)
#
# Needs a Mac with Xcode 15+ and XcodeGen (brew install xcodegen); with VLC also CocoaPods (brew install cocoapods).
set -euo pipefail
cd "$(dirname "$0")/.."

VLC=1
[ "${1:-}" = "--no-vlc" ] && VLC=0

# XcodeGen and CocoaPods write the newest project format (77, Xcode 16); Xcode 15 refuses to open it. Nothing here needs it.
downgrade_format() {
  for f in BGlass.xcodeproj/project.pbxproj Pods/Pods.xcodeproj/project.pbxproj; do
    if [ -f "$f" ]; then sed -i '' 's/objectVersion = 77;/objectVersion = 56;/' "$f"; fi
  done
}

BUILD=build
rm -rf "$BUILD" Pods Podfile.lock BGlass.xcworkspace
echo "==> Generating the Xcode project"
xcodegen generate
downgrade_format
if [ "$VLC" = "1" ]; then
  echo "==> Installing VLC (CocoaPods)"
  pod install
  downgrade_format
  TARGET=(-workspace BGlass.xcworkspace)
else
  TARGET=(-project BGlass.xcodeproj)
fi

echo "==> Building (Release, no code signing)"
set +e
xcodebuild "${TARGET[@]}" -scheme BGlass -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$BUILD" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build > xcodebuild.log 2>&1
STATUS=$?
set -e
tail -n 25 xcodebuild.log
if [ "$STATUS" -ne 0 ]; then
  echo
  echo "==================== ERRORI DI COMPILAZIONE ===================="
  grep -E "error:|fatal error" xcodebuild.log | sort -u | head -60
  echo "================================================================"
  exit "$STATUS"
fi

APP="$BUILD/Build/Products/Release-iphoneos/BGlass.app"
[ -d "$APP" ] || { echo "BGlass.app was not produced"; exit 1; }

echo "==> Packaging the IPA"
rm -rf Payload BGlass.ipa
mkdir Payload
cp -R "$APP" Payload/
zip -qry BGlass.ipa Payload
rm -rf Payload
ls -lh BGlass.ipa
