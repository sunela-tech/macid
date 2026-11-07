#!/usr/bin/env bash
# Builds "build/Mac ID.app" (universal: Apple silicon + Intel). Run on a Mac with Xcode 26+.
#
#   ./scripts/build-app.sh
#
# Optional environment:
#   CLERK_PUBLISHABLE_KEY  defaults to the MacID Clerk app (development instance)
#   MACID_PRICING_URL   page hosting web/pricing/index.html (Clerk PricingTable)
#   SIGN_IDENTITY       "Developer ID Application: Your Name (TEAMID)"; default "-" (ad-hoc, this Mac only)
#   DEVELOPMENT_TEAM    your Apple team ID, when signing with Developer ID
#   VERSION / BUILD_NUMBER
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
# Publishable keys are public by design; this is the "MacID" Clerk app (development instance).
MACID_PRICING_URL="${MACID_PRICING_URL:-https://sunela-tech.github.io/macid/web/pricing/}"
CLERK_PUBLISHABLE_KEY="${CLERK_PUBLISHABLE_KEY:-pk_test_a2Vlbi1ncmlmZm9uLTE3ODkuY2xlcmsuYWNjb3VudHMuZGV2JA}"

if [[ -z "$CLERK_PUBLISHABLE_KEY" ]]; then
  echo "warning: CLERK_PUBLISHABLE_KEY is not set. Sign-in and Pro checks stay off until you rebuild with it." >&2
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "Installing XcodeGen with Homebrew…"
  brew install xcodegen
fi

xcodegen generate --spec project.yml

DERIVED="$ROOT/build/DerivedData"
EXTRA_SIGN_FLAGS=()
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  EXTRA_SIGN_FLAGS+=("OTHER_CODE_SIGN_FLAGS=--timestamp")
fi

# Pretty, annotated output when xcbeautify is installed (it is on GitHub's macOS runners).
FORMAT=(cat)
if command -v xcbeautify >/dev/null 2>&1; then
  FORMAT=(xcbeautify --renderer "${XCBEAUTIFY_RENDERER:-terminal}")
fi

xcodebuild \
  -project MacID.xcodeproj \
  -scheme MacID \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$DERIVED" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CLERK_PUBLISHABLE_KEY="$CLERK_PUBLISHABLE_KEY" \
  MACID_PRICING_URL="$MACID_PRICING_URL" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$SIGN_IDENTITY" DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  ${EXTRA_SIGN_FLAGS[@]+"${EXTRA_SIGN_FLAGS[@]}"} \
  build 2>&1 | "${FORMAT[@]}"

APP_SRC="$DERIVED/Build/Products/Release/Mac ID.app"
rm -rf "$ROOT/build/Mac ID.app"
cp -R "$APP_SRC" "$ROOT/build/"

codesign --verify --deep --strict --verbose=2 "$ROOT/build/Mac ID.app"
echo "Built: build/Mac ID.app ($VERSION, signed with: $SIGN_IDENTITY)"
