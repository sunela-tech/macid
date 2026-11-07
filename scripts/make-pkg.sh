#!/usr/bin/env bash
# Packages "build/Mac ID.app" into build/MacID-<version>.pkg that installs to /Applications.
#
# Optional environment:
#   INSTALLER_IDENTITY  "Developer ID Installer: Your Name (TEAMID)" to sign the installer
#   NOTARY_PROFILE      keychain profile from `xcrun notarytool store-credentials` to notarize + staple
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Mac ID.app"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")}"
PKG="$ROOT/build/MacID-$VERSION.pkg"

[[ -d "$APP" ]] || { echo "Run scripts/build-app.sh first." >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/root/Applications"
cp -R "$APP" "$WORK/root/Applications/"

# Always install into /Applications, even if another copy exists elsewhere.
pkgbuild --analyze --root "$WORK/root" "$WORK/component.plist"
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$WORK/component.plist"

pkgbuild \
  --root "$WORK/root" \
  --component-plist "$WORK/component.plist" \
  --identifier app.macid.MacID \
  --version "$VERSION" \
  --install-location / \
  "$WORK/MacID-component.pkg"

SIGN_ARGS=()
if [[ -n "${INSTALLER_IDENTITY:-}" ]]; then
  SIGN_ARGS+=(--sign "$INSTALLER_IDENTITY" --timestamp)
fi

rm -f "$PKG"
productbuild --package "$WORK/MacID-component.pkg" ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} "$PKG"

if [[ -n "${NOTARY_PROFILE:-}" && -n "${INSTALLER_IDENTITY:-}" ]]; then
  xcrun notarytool submit "$PKG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$PKG"
fi

echo "Built: $PKG"
