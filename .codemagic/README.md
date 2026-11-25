# Codemagic Unsigned IPA Build

This directory and the root [`codemagic.yaml`](../codemagic.yaml) configure Codemagic to build an unsigned iOS `.ipa` for **Trinote** (including the embedded `TrinoteShare` share extension) without touching any upstream files.

## Conflict-Free Fork Layout

To prevent merge conflicts when syncing with upstream `main`:

- **No upstream files are modified in git** (`project.yml`, `Scripts/*`, `Trinote/*`, `TrinoteShare/*`, `TrinoteShared/*`, `.gitignore`, etc. remain untouched).
- All Codemagic files live solely in:
  - `codemagic.yaml` (required at the repository root by Codemagic)
  - `.codemagic/build-unsigned-ipa.sh`
  - `.codemagic/README.md`
- At build time, `.codemagic/build-unsigned-ipa.sh` dynamically runs `xcodegen generate` against whatever `project.yml` upstream currently provides, disables signing strictly via `xcodebuild` command-line overrides, and reads the version/build number from the archived `Info.plist`.

## Optional: Custom App Group for Third-Party Signing Certs

Upstream hardcodes `group.com.trinote`, which belongs to the upstream developer's Apple Developer Team. If your signing certificate's `.mobileprovision` grants a different App Group ID (e.g., `group.xxxxxxxx.1`), configure it privately in Codemagic so it is never committed to a public repo:

1. In Codemagic, open **App settings → Environment variables**.
2. Add a variable:
   - **Variable name**: `CUSTOM_APP_GROUP_ID`
   - **Variable value**: your profile's App Group ID (for example `group.xxxxxxxx.1`)
   - **Group**: `trinote_signing`
   - Optionally check **Secure** to mask it in build logs.
3. Run a build. The script temporarily substitutes `group.com.trinote` with `CUSTOM_APP_GROUP_ID` during the CI build (and restores the working tree on exit) and ad-hoc signs both `TrinoteShare.appex` and `Trinote.app` with their `.entitlements` files so your signer preserves the App Group capability.

To disable ad-hoc entitlement embedding and produce a raw stripped IPA instead, set `EMBED_ADHOC_ENTITLEMENTS: "false"` in `codemagic.yaml` or the `trinote_signing` group.

## Recommended Git Sync Workflow

```bash
# One-time setup: add the upstream repository
git remote add upstream <upstream-repo-url>

# Sync future upstream changes without conflicts
git fetch upstream
git merge upstream/main
# (or: git rebase upstream/main)
```

Alternatively, you can keep `main` strictly tracking upstream and keep these Codemagic files on a dedicated `codemagic` branch — `codemagic.yaml` triggers on both `main` and `codemagic` (plus tags and manual runs).

## Build Output

Codemagic publishes the unsigned `.ipa` as an artifact at:

```text
build/codemagic/ipa/Trinote-<version>-b<build>-unsigned.ipa
```
