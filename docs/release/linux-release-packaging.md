# Vityo Linux Release Packaging

**Purpose:** Define the Linux desktop release packaging requirements for Vityo,
including desktop entry specification, icon policy, executable permissions,
AppStream metadata, update policy, release notes, and rollback/recovery
evidence.

**Owner:** Governance owner (CODEOWNERS -> governance domain)
**Last updated:** 2026-06-29
**Status:** Draft - connected to release gates

## 1. Scope

This document covers the Linux desktop release artifact for Vityo as a native
Flutter desktop app. It applies when a formal Linux release is claimed in the
release record.

The Linux release artifact is:

- A native `flutter build linux --release` binary bundle.
- Packaged as a `.deb` package for Debian/Ubuntu (amd64), with optional
  Flatpak/AppImage coverage.
- Verified by the CI `local-ci-gate` Linux job and the release-readiness gate.

## 2. Desktop Entry

The desktop entry file is at `packaging/linux/io.vityo.desktop`.

**Requirements:**

| Field | Value | Notes |
|-------|-------|-------|
| `Type` | `Application` | Standard desktop application |
| `Name` | `Vityo` | Must match the product name |
| `GenericName` | `Integrated Development Environment` | Desktop search |
| `Categories` | `Development;IDE;` | FreeDesktop.org menu placement |
| `Exec` | `vityo %F` | `%F` for file-open support |
| `Icon` | `io.vityo` | Matches the icon basename in `packaging/linux/icons/` |
| `Terminal` | `false` | No terminal wrapper needed |
| `MimeType` | `text/plain;text/x-styio;inode/directory;` | File associations |

**Validation:**

```bash
desktop-file-validate packaging/linux/io.vityo.desktop
```

## 3. Application Icons

Icons must be installed to the standard FreeDesktop.org icon theme paths:

| Size | Path | Format |
|------|------|--------|
| 256x256 | `/usr/share/icons/hicolor/256x256/apps/io.vityo.png` | PNG |
| scalable | `/usr/share/icons/hicolor/scalable/apps/io.vityo.svg` | SVG |

Icons live in source under `packaging/linux/icons/` and are copied by the
release build script.

## 4. AppStream Metadata

The AppStream file is at `packaging/linux/io.vityo.metainfo.xml`.

**Validation:**

```bash
appstreamcli validate packaging/linux/io.vityo.metainfo.xml
```

## 5. Executable Permissions

The main Flutter release binary lives at:

```
frontend/vityo_app/build/linux/x64/release/bundle/vityo
```

During packaging:
1. The binary must have executable bit set (`chmod +x`).
2. A wrapper script `/usr/bin/vityo` (or `/usr/local/bin/vityo`) is installed
   that launches the Flutter bundle.
3. The wrapper must NOT require `flutter` or Dart SDK at runtime.
4. The bundle's `lib/` directory and all `.so` files must have correct
   permissions (644 for libraries, 755 for binaries).

## 6. Update Policy

| Mechanism | Priority | Status |
|-----------|----------|--------|
| `.deb` package from GitHub Releases | Primary | Planned |
| Built-in self-update (in-app) | Secondary | Not implemented |
| Flatpak | Tertiary | Not implemented |
| AppImage | Quaternary | Not implemented |

For `.deb` distribution:
1. Each release publishes a `.deb` to GitHub Releases.
2. Users install via `dpkg -i vityo_<version>_amd64.deb`.
3. Update check: `apt update && apt upgrade` (if added to a repo).

## 7. Release Notes

Every formal Linux release requires:

1. A CHANGELOG or release notes entry in the release record.
2. Documentation of any Linux-specific changes, regressions, or known issues.
3. Upgrade/downgrade path instructions.
4. System requirements (Debian 13 / Ubuntu 24.04+, GTK 3.24+, etc.).

## 8. Rollback And Recovery

1. The previous `.deb` version is retained in GitHub Releases for downgrade.
2. Uninstall: `dpkg -r vityo` removes the application and metadata.
3. Data preservation: `dpkg -r` does NOT remove `~/.config/vityo/` or
   `~/.local/share/vityo/` — user data survives uninstall.
4. Purge: `dpkg --purge vityo` removes configuration and data directories.

## 9. Gate Integration

The release-readiness gate (`scripts/release-readiness-gate.py`) verifies:

- `packaging/linux/io.vityo.desktop` exists.
- `packaging/linux/io.vityo.metainfo.xml` exists.
- `packaging/linux/DEBIAN/control` exists (for `.deb` release).

The delivery gate (`scripts/delivery-gate.sh`) passes these checks:

```bash
python3 scripts/release-readiness-gate.py --skip-build  # static packaging check
desktop-file-validate packaging/linux/io.vityo.desktop   # if available
```

## 10. Current Gaps

| Gap | Priority | Owner |
|-----|----------|-------|
| Icon SVG/PNG assets not yet created | Medium | Design |
| `.deb` packaging script not yet implemented | High | Release |
| `appstreamcli validate` not in CI gate | Low | Governance |
| Flutter Linux release bundle size optimization | Low | Performance |
| Formal release evidence still needs signed/distributed package, install/update/uninstall proof, and rollback proof | High | Release |

## 11. Related Documents

- [Linux Desktop Adaptation Plan](../design/Vityo-Linux-Desktop-Adaptation-Plan.md)
- [BUILD-AND-DEV-ENV.md](../BUILD-AND-DEV-ENV.md)
- [Release Checklist](../governance/RELEASE-CHECKLIST.md)
- [packaging/linux/README.md](../../packaging/linux/README.md)
