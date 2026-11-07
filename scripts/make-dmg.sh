#!/usr/bin/env bash
# Packages "build/Mac ID.app" into build/MacID-<version>.dmg (drag-to-Applications layout).
#
# Optional environment:
#   SIGN_IDENTITY    "Developer ID Application: …" to sign the disk image
#   NOTARY_PROFILE   keychain profile from `xcrun notarytool store-credentials` to notarize + staple
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Mac ID.app"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")}"
DMG="$ROOT/build/MacID-$VERSION.dmg"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

[[ -d "$APP" ]] || { echo "Run scripts/build-app.sh first." >&2; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "Mac ID" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG"

if [[ "$SIGN_IDENTITY" != "-" ]]; then
  codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

echo "Built: $DMG"
