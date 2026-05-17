# Dependency Usage Boundary

**Purpose:** Record dependency authorization boundaries for `Vityo`.

**Last updated:** 2026-04-24

`Vityo` is an Apache-2.0 Flutter/Dart application source project. Its current app, prototype, runner, docs, and test dependency boundary is:

- Flutter SDK and Dart SDK drive the frontend workspace and test harness.
- `cupertino_icons`, `shared_preferences`, `path_provider`, `flutter_test`, and `flutter_lints` are Flutter/Dart dependencies governed by the app manifests.
- `playwright-core` is prototype screenshot and browser automation tooling.
- CMake, PkgConfig, Android Gradle, Apple platform runner toolchains, GitHub Actions, Python standard library tooling, and Bash scripts are external build, platform, CI, and automation surfaces.
- UI assets must remain covered by documented open-source asset evidence before promotion into product surfaces.

Dependency policy:

- No dependency may require commercial authorization, paid licensing, subscription access, membership access, trial-only terms, proprietary-use approval, or private registry access.
- Any future dependency must be listed here with its license evidence, source boundary, and usage boundary before it can pass audit.
- Prototype-only dependencies must stay prototype-scoped and must not become product runtime requirements without this file being updated.
- Generated reports and gate summaries must summarize dependency, UI asset, and license evidence without copying target repository source.
