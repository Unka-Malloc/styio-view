# Styio IDE Linux Packaging

**Purpose:** Define the independently versioned Linux Nightly Debian package.

**Last updated:** 2026-07-20

## Directory Layout

```
packaging/linux/
├── io.styio.ide.desktop       # FreeDesktop.org Desktop Entry
├── io.styio.ide.metainfo.xml  # AppStream metadata (software center)
├── nightly.json           # Package inputs, signing and update policy
├── DEBIAN/                # Debian/Ubuntu control file
│   └── control
└── README.md              # This file
```

## Build Integration

The Linux CI job builds the Flutter bundle, runs
`python3 scripts/package-nightly.py --platform linux`, installs the resulting
package with `dpkg`, probes startup through Xvfb, and uploads the package plus
its machine-readable receipt. The release-readiness gate validates the static
package contract even when `--skip-build` is used.

## Required Files for a Formal Linux Release

| File | Purpose | Required |
|------|---------|----------|
| `io.styio.ide.desktop` | FreeDesktop.org menu entry, MIME associations | Formal release |
| `io.styio.ide.metainfo.xml` | AppStream metadata (GNOME Software, KDE Discover) | Formal release |
| Application icon | Installed at the standard hicolor path | Nightly package |
| `/usr/bin/styio-ide` wrapper | PATH integration and executable permissions | Nightly package |
| `nightly.json` signing/update policy | Fail-closed release metadata | Nightly package |

Repository signing is not configured. Therefore Linux automatic updates remain
disabled and the package is manual-trust Nightly evidence only.
