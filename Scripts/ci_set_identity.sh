#!/usr/bin/env bash
# Rewrites the signing identity and version in project.yml before `xcodegen generate`.
# Every argument is optional; unset ones keep what project.yml already has.
#
#   BUNDLE_ID        app bundle ID (the share extension gets "$BUNDLE_ID.fileshare")
#   APP_GROUP_ID     App Group shared by the app and the extension (default: group.$BUNDLE_ID)
#   APPLE_TEAM_ID    Apple Developer team ID
#   TRINOTE_BUILD_NUMBER  CFBundleVersion
#   MARKETING_VERSION_OVERRIDE  CFBundleShortVersionString
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
YML="${ROOT}/project.yml"

if [[ -n "${BUNDLE_ID:-}" && -z "${APP_GROUP_ID:-}" ]]; then
  APP_GROUP_ID="group.${BUNDLE_ID}"
fi

set_key() {
  local key="$1" value="$2"
  [[ -z "$value" ]] && return 0
  # Only the first (project-level) occurrence of each key is rewritten.
  python3 - "$YML" "$key" "$value" <<'PY'
import re, sys
path, key, value = sys.argv[1:]
text = open(path, encoding="utf-8").read()
text, n = re.subn(rf'^(\s*){key}:.*$', rf'\g<1>{key}: "{value}"', text, count=1, flags=re.M)
if n != 1:
    sys.exit(f"ci_set_identity: {key} not found in project.yml")
open(path, "w", encoding="utf-8").write(text)
PY
  echo "ci_set_identity: ${key} = ${value}"
}

set_key TRINOTE_BUNDLE_ID "${BUNDLE_ID:-}"
set_key TRINOTE_APP_GROUP "${APP_GROUP_ID:-}"
set_key DEVELOPMENT_TEAM "${APPLE_TEAM_ID:-}"
set_key CURRENT_PROJECT_VERSION "${TRINOTE_BUILD_NUMBER:-}"
set_key MARKETING_VERSION "${MARKETING_VERSION_OVERRIDE:-}"
