#!/usr/bin/env bash
# Builds an unsigned iOS .ipa for Trinote directly from upstream's project.yml
# without modifying any upstream-tracked files in git.
#
# Optional environment variables:
#   CUSTOM_APP_GROUP_ID       Override upstream's group.com.trinote at build time
#                             to match an App Group granted by your signing profile.
#   EMBED_ADHOC_ENTITLEMENTS  When "true" (default), ad-hoc signs the staged .app
#                             and .appex bundles with their .entitlements so signers
#                             preserve the App Group capability.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

XCODE_SCHEME="${XCODE_SCHEME:-Trinote}"
XCODE_CONFIGURATION="${XCODE_CONFIGURATION:-Release}"
CUSTOM_APP_GROUP_ID="${CUSTOM_APP_GROUP_ID:-}"
EMBED_ADHOC_ENTITLEMENTS="${EMBED_ADHOC_ENTITLEMENTS:-true}"
DEFAULT_APP_GROUP_ID="group.com.trinote"

BUILD_DIR="${BUILD_DIR:-${REPO_ROOT}/build/codemagic}"
ARCHIVE_PATH="${BUILD_DIR}/${XCODE_SCHEME}.xcarchive"
DERIVED_DATA_PATH="${BUILD_DIR}/DerivedData"
IPA_DIR="${BUILD_DIR}/ipa"
PAYLOAD_STAGE="${BUILD_DIR}/payload_stage"
SPM_CACHE_DIR="${SPM_CACHE_DIR:-${HOME}/Library/Caches/TrinoteSPM}"

BACKUP_DIR=""
PATCHED_FILES=()

cleanup() {
  if [[ -n "${BACKUP_DIR}" && -d "${BACKUP_DIR}" ]]; then
    for rel_path in "${PATCHED_FILES[@]}"; do
      if [[ -f "${BACKUP_DIR}/${rel_path}" ]]; then
        cp "${BACKUP_DIR}/${rel_path}" "${REPO_ROOT}/${rel_path}"
      fi
    done
    rm -rf "${BACKUP_DIR}"
  fi
}
trap cleanup EXIT

apply_custom_app_group() {
  local new_group="$1"

  if [[ "${new_group}" =~ [[:space:]\"\'\<\>] ]]; then
    echo "ERROR: CUSTOM_APP_GROUP_ID contains invalid characters." >&2
    exit 1
  fi

  echo "==> Applying custom App Group override from CUSTOM_APP_GROUP_ID (ephemeral build-time patch)..."
  BACKUP_DIR="$(mktemp -d)"

  local targets=(
    "TrinoteShared/SharedImportConstants.swift"
    "TrinoteShared/SharedImportStore.swift"
    "Trinote/Trinote.entitlements"
    "TrinoteShare/TrinoteShare.entitlements"
  )

  for rel_path in "${targets[@]}"; do
    local full_path="${REPO_ROOT}/${rel_path}"
    if [[ ! -f "${full_path}" ]]; then
      echo "ERROR: Expected file not found for App Group override: ${rel_path}" >&2
      exit 1
    fi
    mkdir -p "${BACKUP_DIR}/$(dirname "${rel_path}")"
    cp "${full_path}" "${BACKUP_DIR}/${rel_path}"
    PATCHED_FILES+=("${rel_path}")

    python3 - "${full_path}" "${DEFAULT_APP_GROUP_ID}" "${new_group}" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
old, new = sys.argv[2], sys.argv[3]
text = path.read_text(encoding="utf-8")
if old not in text:
    raise SystemExit(f"ERROR: '{old}' not found in {path}")
path.write_text(text.replace(old, new), encoding="utf-8")
PY
    echo "    Patched ${rel_path}"
  done
}

echo "==> Environment"
xcodebuild -version

if [[ -n "${CUSTOM_APP_GROUP_ID}" && "${CUSTOM_APP_GROUP_ID}" != "${DEFAULT_APP_GROUP_ID}" ]]; then
  apply_custom_app_group "${CUSTOM_APP_GROUP_ID}"
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "==> Installing XcodeGen via Homebrew..."
  HOMEBREW_NO_AUTO_UPDATE=1 brew install xcodegen
fi
echo "==> XcodeGen: $(xcodegen --version)"

echo "==> Generating Xcode project from project.yml..."
xcodegen generate --spec "${REPO_ROOT}/project.yml"

XCODE_PROJECT="${XCODE_PROJECT:-}"
if [[ -z "${XCODE_PROJECT}" ]]; then
  if [[ -d "${REPO_ROOT}/${XCODE_SCHEME}.xcodeproj" ]]; then
    XCODE_PROJECT="${REPO_ROOT}/${XCODE_SCHEME}.xcodeproj"
  else
    XCODE_PROJECT="$(find "${REPO_ROOT}" -maxdepth 1 -name '*.xcodeproj' -print -quit)"
  fi
fi

if [[ -z "${XCODE_PROJECT}" || ! -d "${XCODE_PROJECT}" ]]; then
  echo "ERROR: Could not locate generated .xcodeproj in ${REPO_ROOT}" >&2
  exit 1
fi
echo "==> Using Xcode project: ${XCODE_PROJECT}"

rm -rf "${ARCHIVE_PATH}" "${IPA_DIR}" "${PAYLOAD_STAGE}"
mkdir -p "${BUILD_DIR}" "${IPA_DIR}" "${SPM_CACHE_DIR}"

echo "==> Resolving Swift Package Manager dependencies..."
xcodebuild -resolvePackageDependencies \
  -project "${XCODE_PROJECT}" \
  -scheme "${XCODE_SCHEME}" \
  -clonedSourcePackagesDirPath "${SPM_CACHE_DIR}" \
  -skipPackagePluginValidation \
  -skipMacroValidation

echo "==> Archiving unsigned release build (scheme=${XCODE_SCHEME}, config=${XCODE_CONFIGURATION})..."
xcodebuild archive \
  -project "${XCODE_PROJECT}" \
  -scheme "${XCODE_SCHEME}" \
  -configuration "${XCODE_CONFIGURATION}" \
  -sdk iphoneos \
  -destination "generic/platform=iOS" \
  -archivePath "${ARCHIVE_PATH}" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  -clonedSourcePackagesDirPath "${SPM_CACHE_DIR}" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="" \
  DEVELOPMENT_TEAM="" \
  PROVISIONING_PROFILE_SPECIFIER=""

APP_PATH="$(find "${ARCHIVE_PATH}/Products/Applications" -maxdepth 1 -name '*.app' -print -quit)"
if [[ -z "${APP_PATH}" || ! -d "${APP_PATH}" ]]; then
  echo "ERROR: No .app bundle found under ${ARCHIVE_PATH}/Products/Applications" >&2
  exit 1
fi

APP_BUNDLE_NAME="$(basename "${APP_PATH}")"
APP_NAME="${APP_BUNDLE_NAME%.app}"
INFO_PLIST="${APP_PATH}/Info.plist"

APP_VERSION=""
APP_BUILD=""
if [[ -x "/usr/libexec/PlistBuddy" && -f "${INFO_PLIST}" ]]; then
  APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}" 2>/dev/null || true)"
  APP_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${INFO_PLIST}" 2>/dev/null || true)"
fi

IPA_BASENAME="${APP_NAME}"
if [[ -n "${APP_VERSION}" ]]; then
  IPA_BASENAME="${IPA_BASENAME}-${APP_VERSION}"
fi
if [[ -n "${APP_BUILD}" ]]; then
  IPA_BASENAME="${IPA_BASENAME}-b${APP_BUILD}"
fi
IPA_BASENAME="${IPA_BASENAME}-unsigned"
IPA_PATH="${IPA_DIR}/${IPA_BASENAME}.ipa"

echo "==> Staging Payload/${APP_BUNDLE_NAME}..."
mkdir -p "${PAYLOAD_STAGE}/Payload"
if command -v ditto >/dev/null 2>&1; then
  ditto "${APP_PATH}" "${PAYLOAD_STAGE}/Payload/${APP_BUNDLE_NAME}"
else
  cp -a "${APP_PATH}" "${PAYLOAD_STAGE}/Payload/${APP_BUNDLE_NAME}"
fi

STAGED_APP="${PAYLOAD_STAGE}/Payload/${APP_BUNDLE_NAME}"

# Strip any stray code signature metadata or embedded profiles before packaging/ad-hoc signing.
find "${STAGED_APP}" -name "_CodeSignature" -type d -prune -exec rm -rf {} +
find "${STAGED_APP}" -name "embedded.mobileprovision" -type f -delete

if [[ -d "${STAGED_APP}/PlugIns" ]]; then
  echo "==> Embedded PlugIns:"
  ls -la "${STAGED_APP}/PlugIns"
fi

if [[ "${EMBED_ADHOC_ENTITLEMENTS}" == "true" ]] && command -v codesign >/dev/null 2>&1; then
  echo "==> Embedding entitlements via ad-hoc codesign..."

  if [[ -d "${STAGED_APP}/Frameworks" ]]; then
    while IFS= read -r -d '' fw; do
      codesign --force --sign - "${fw}"
    done < <(find "${STAGED_APP}/Frameworks" -maxdepth 1 \( -name '*.framework' -o -name '*.dylib' \) -print0)
  fi

  if [[ -d "${STAGED_APP}/PlugIns" ]]; then
    while IFS= read -r -d '' appex; do
      appex_name="$(basename "${appex}" .appex)"
      appex_entitlements="${REPO_ROOT}/${appex_name}/${appex_name}.entitlements"
      if [[ -f "${appex_entitlements}" ]]; then
        codesign --force --sign - --entitlements "${appex_entitlements}" "${appex}"
        echo "    Ad-hoc signed ${appex_name}.appex with ${appex_name}.entitlements"
      else
        codesign --force --sign - "${appex}"
        echo "    Ad-hoc signed ${appex_name}.appex"
      fi
    done < <(find "${STAGED_APP}/PlugIns" -maxdepth 1 -name '*.appex' -print0)
  fi

  app_entitlements="${REPO_ROOT}/${APP_NAME}/${APP_NAME}.entitlements"
  if [[ -f "${app_entitlements}" ]]; then
    codesign --force --sign - --entitlements "${app_entitlements}" "${STAGED_APP}"
    echo "    Ad-hoc signed ${APP_BUNDLE_NAME} with ${APP_NAME}.entitlements"
    if codesign -d --entitlements :- "${STAGED_APP}" 2>/dev/null | grep -q "com.apple.security.application-groups"; then
      echo "==> Verified com.apple.security.application-groups entitlement is embedded in ${APP_BUNDLE_NAME}"
    fi
  else
    codesign --force --sign - "${STAGED_APP}"
    echo "    Ad-hoc signed ${APP_BUNDLE_NAME}"
  fi
fi

echo "==> Packaging unsigned IPA: ${IPA_PATH}"
(
  cd "${PAYLOAD_STAGE}"
  zip -qry "${IPA_PATH}" Payload
)

rm -rf "${PAYLOAD_STAGE}"

echo "==> Unsigned IPA created:"
ls -lh "${IPA_PATH}"
