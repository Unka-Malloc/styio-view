# Vityo Windows Release Packaging

**Purpose:** Define Windows desktop release packaging requirements for Vityo, including native build evidence, installer behavior, PATH and file associations, update and repair behavior, and rollback evidence.

**Last updated:** 2026-06-29
**Status:** Draft - connected to release gates

## 1. Scope

This document covers the Windows desktop release artifact for Vityo as a native Flutter desktop app. It applies when a formal Windows release is claimed in the release record.

The Windows release artifact is:

- A native `flutter build windows --release` bundle.
- Distributed through a production installer or package format selected by the release owner.
- Verified by the hosted `windows-native` workflow and by a release record that attaches install/update/uninstall and rollback evidence.

## 2. CI Evidence Floor

The hosted workflow at `.github/workflows/windows-native.yml` must:

1. Run on `windows-latest`.
2. Provide `STYIO`, `STYIO_CHROME_PATH`, `CHROME_EXECUTABLE`, and `PYTHON_BIN` to the delivery gate.
3. Run `scripts/delivery-gate.sh --mode push` without `--skip-health` or `--skip-ecosystem`.
4. Run `flutter analyze`.
5. Run `flutter build windows --release`.
6. Upload Windows coverage and release build artifacts.

This proves the default CI floor. It does not prove formal distribution, signing, installer behavior, update behavior, or rollback.

## 3. Installer Requirements

A formal Windows release must define and verify:

| Requirement | Evidence |
|-------------|----------|
| Install path | Default install location and per-user or machine-wide scope are documented. |
| PATH behavior | Any command-line launcher or PATH entry is documented and reversible. |
| File associations | `.styio`, text files, and workspace-directory associations are either implemented and tested or explicitly unsupported. |
| Repair | Re-running the installer repairs missing binaries, metadata, shortcuts, and file associations. |
| Update | Installing a newer package preserves user data and replaces binaries atomically enough to recover from interruption. |
| Rollback | Downgrade or rollback path is documented, including user-data preservation rules. |
| Uninstall | Uninstall removes application binaries, shortcuts, launcher entries, and associations while preserving user data unless purge is explicitly selected. |

## 4. Runtime Data Preservation

The installer must not delete user project data during normal uninstall or update. User data locations must be documented in the release record, including:

1. Configuration directory.
2. Module package cache and staged updates.
3. Logs and diagnostics.
4. Workspace-local metadata.

## 5. Current Local Blockers

Local Windows Flutter plugin tests are blocked on this machine because native plugin builds require Windows symlink support. Enable Windows Developer Mode or equivalent symlink privileges before claiming local Windows native test evidence.

Hosted `windows-latest` CI remains the default Windows release-build evidence path until local Developer Mode is available.

## 6. Current Gaps

| Gap | Priority | Owner |
|-----|----------|-------|
| Production installer/package format is not selected in this repository | High | Release |
| Code signing evidence is not attached | High | Release |
| Install/update/uninstall/repair/rollback proof is not attached | High | Release |
| Local Windows native Flutter tests are blocked by symlink privilege | Medium | Developer environment |

## 7. Related Documents

- [Windows Desktop Adaptation Plan](../design/Vityo-Windows-Desktop-Adaptation-Plan.md)
- [BUILD-AND-DEV-ENV.md](../BUILD-AND-DEV-ENV.md)
- [Release Checklist](../governance/RELEASE-CHECKLIST.md)
- [Local Validation Evidence](./local-validation-evidence.md)
