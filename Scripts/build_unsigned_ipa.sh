#!/usr/bin/env bash
# Builds an unsigned Trinote.ipa for sideloading (AltStore, SideStore, Sideloadly, …),
# which re-sign it with your own Apple ID. Needs macOS with Xcode 26+ and XcodeGen.
#
#   ./Scripts/build_unsigned_ipa.sh [output-dir]   (default: build/ipa)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-${ROOT}/build/ipa}"
ARCHIVE="${ROOT}/build/Trinote.xcarchive"

cd "$ROOT"
[[ -d Trinote.xcodeproj ]] || xcodegen generate

rm -rf "$ARCHIVE" "$OUT"
xcodebuild archive \
  -project Trinote.xcodeproj \
  -scheme Trinote \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  | { command -v xcpretty >/dev/null && xcpretty || cat; }

APP="${ARCHIVE}/Products/Applications/Trinote.app"
[[ -d "$APP" ]] || { echo "build_unsigned_ipa: $APP was not produced" >&2; exit 1; }

# Ad-hoc sign with the entitlements so sideloading tools see the App Group the share
# extension needs; they replace this signature with one from your Apple ID.
APP_GROUP="$(grep -E '^[[:space:]]*TRINOTE_APP_GROUP:' project.yml | head -1 | sed -E 's/.*:[[:space:]]*"?([^"]*)"?[[:space:]]*$/\1/')"
for fw in "${APP}"/Frameworks/*; do
  if [[ -e "$fw" ]]; then codesign --force --sign - "$fw"; fi
done
ENT_DIR="$(mktemp -d)"
for pair in "TrinoteShare/TrinoteShare.entitlements:${APP}/PlugIns/TrinoteShare.appex" \
            "Trinote/Trinote.entitlements:${APP}"; do
  src="${pair%%:*}" bundle="${pair#*:}"
  [[ -d "$bundle" ]] || continue
  sed "s/\$(TRINOTE_APP_GROUP)/${APP_GROUP}/" "$src" > "${ENT_DIR}/$(basename "$src")"
  codesign --force --sign - --entitlements "${ENT_DIR}/$(basename "$src")" "$bundle"
done
rm -rf "$ENT_DIR"

STAGE="$(mktemp -d)"
mkdir -p "${STAGE}/Payload" "$OUT"
cp -R "$APP" "${STAGE}/Payload/"
(cd "$STAGE" && zip -qry "${OUT}/Trinote-unsigned.ipa" Payload)
rm -rf "$STAGE"
echo "build_unsigned_ipa: ${OUT}/Trinote-unsigned.ipa"
