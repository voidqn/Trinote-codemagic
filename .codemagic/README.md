# Codemagic Unsigned IPA Build

This directory and the root [`codemagic.yaml`](../codemagic.yaml) configure Codemagic to build an unsigned iOS `.ipa` for **Trinote** (including the embedded `TrinoteShare` share extension) without touching any upstream files.

## Conflict-Free Fork Layout

To prevent merge conflicts when syncing with upstream `main`:

- **No upstream files are modified** (`project.yml`, `Scripts/*`, `Trinote/*`, `TrinoteShare/*`, `.gitignore`, etc. remain untouched).
- All Codemagic files live solely in:
  - `codemagic.yaml` (required at the repository root by Codemagic)
  - `.codemagic/build-unsigned-ipa.sh`
  - `.codemagic/README.md`
- At build time, `.codemagic/build-unsigned-ipa.sh` dynamically runs `xcodegen generate` against whatever `project.yml` upstream currently provides, disables signing strictly via `xcodebuild` command-line overrides, and reads the version/build number from the archived `Info.plist`.

### Recommended Git Sync Workflow

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

You can sign and install the resulting unsigned `.ipa` using your preferred signing/sideloading tool (e.g., AltStore, SideStore, Sideloadly, TrollStore, or `zsign`).
