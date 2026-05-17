# Technology And Component Inventory

**Purpose:** Define the required technology-stack, internal-component, open-source-component, and dependency-manifest inventory for `Vityo`.

**Last updated:** 2026-04-24

This document is the repository-local maintenance rule for the manifest inventory audited by `styio-audit`. The canonical audit module must list the same surfaces in `for-vityo/module.json`; if this document and the audit manifest diverge, the change is not closed.

## Required Inventory Fields

Every audit manifest for this repository must maintain these non-empty lists:

1. `technology_stack`
2. `internal_components`
3. `open_source_components`
4. `dependency_manifests`

Missing or stale lists are audit failures. They block license, commercial-risk, ownership, and usage-boundary review because auditors cannot prove what stack and components are in scope.

## Current Inventory

Technology stack:

- Flutter and Dart frontend workspace.
- Android, iOS, macOS, Linux, Windows, and web platform runners.
- CMake native runner integration for desktop platforms.
- JavaScript, HTML, and CSS prototype with Playwright screenshot tooling.
- Python and Bash repository, docs, and device/profile scripts.
- GitHub Actions workflow automation.

Internal components:

- Workspace document store, editor controller, selection, persistence, and shell state.
- Backend toolchain and integration adapters for local, hosted, and web execution routes.
- Module host, module manifests, capability matrices, staged updates, and platform visibility.
- Runtime replay surfaces, hosted payload codecs, debug console summaries, and graph/lane models.
- Prototype UI and development server security harness.
- Docs, product, device, and delivery gate scripts.

Open-source and external components:

- Flutter SDK and Dart SDK.
- `cupertino_icons`.
- `shared_preferences`.
- `path_provider`.
- `flutter_test`.
- `flutter_lints`.
- `playwright-core`.
- `PkgConfig`.
- Android Gradle and platform runner toolchains.
- Apple platform runner toolchains.
- GitHub Actions.

Dependency manifest surfaces:

- `frontend/vityo_app/pubspec.yaml`.
- `prototype/package.json`.
- `frontend/vityo_app/linux/CMakeLists.txt`.
- `frontend/vityo_app/linux/flutter/CMakeLists.txt`.
- `frontend/vityo_app/windows/CMakeLists.txt`.
- `frontend/vityo_app/windows/flutter/CMakeLists.txt`.
- Android Gradle files.
- `.github/workflows/*.yml`.

## Maintenance Rule

Update this document and the matching `styio-audit` project module in the same change whenever any of these occur:

1. A language, SDK, runtime, build system, CI system, package manager, platform runner, or generated-code tool is added or removed.
2. A first-party editor, adapter, module-host, runtime, prototype, gate, or workflow boundary is added, renamed, or retired.
3. An open-source or external component is introduced, removed, vendored, promoted from prototype-only to product use, or given a new usage boundary.
4. A dependency manifest is added, removed, renamed, or moved.
5. License, Apache-2.0, commercial-authorization, subscription, membership, trial-only, proprietary-use, or UI asset-source evidence changes.

For new external dependencies, update [THIRD-PARTY.md](./THIRD-PARTY.md), [OPEN-SOURCE-UI-ASSET-POLICY.md](./OPEN-SOURCE-UI-ASSET-POLICY.md) when UI assets are involved, and this inventory together before the change can pass audit.
