# Vityo Linux Packaging

**Purpose:** Provide Linux desktop release packaging structure for Vityo,
including desktop entry, AppStream metadata, icon, executable permissions,
update policy, and Debian/Ubuntu packaging templates.

**Last updated:** 2026-06-29

## Directory Layout

```
packaging/linux/
├── io.vityo.desktop       # FreeDesktop.org Desktop Entry
├── io.vityo.metainfo.xml  # AppStream metadata (software center)
├── icons/                 # Application icons (installed by CI/release script)
│   ├── io.vityo.png       #   (generated or placed at build time)
│   └── io.vityo.svg       #   (vector icon source)
├── DEBIAN/                # Debian/Ubuntu control files (optional)
│   └── control
├── io.vityo.binstall      # Binstall metadata (optional, planned)
└── README.md              # This file
```

## Build Integration

The CI job `local-ci-gate.yml` builds `flutter build linux --release` and should
verify that packaging metadata exists before the release artifact is created.

Release packaging metadata is validated by the release-readiness gate when the
`--linux` flag is passed (or on ubuntu-latest runners).

## Required Files for a Formal Linux Release

| File | Purpose | Required |
|------|---------|----------|
| `io.vityo.desktop` | FreeDesktop.org menu entry, MIME associations | Formal release |
| `io.vityo.metainfo.xml` | AppStream metadata (GNOME Software, KDE Discover) | Formal release |
| Application icon (SVG/PNG) | Desktop icon in standard sizes | Formal release |
| Executable wrapper/script | Proper executable bit, PATH integration | Formal release |
| Update metadata | Update policy (AppImage, Flatpak, .deb repo, or self-update) | Formal release |
| Release notes | Changelog, upgrading instructions | Formal release |