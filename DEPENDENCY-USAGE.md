# Dependency Usage Boundary

**Purpose:** Record dependency authorization boundaries for `Vityo`.

**Last updated:** 2026-06-25

`Vityo` is an Apache-2.0 Flutter/Dart application source project. Its current app, prototype, runner, docs, and test dependency boundary is:

## Runtime Dependencies

| Dependency | Version | License | Source Boundary | Usage Boundary | Classification |
|---|---|---|---|---|---|
| `flutter` (SDK) | Flutter SDK | BSD-3-Clause | Flutter framework SDK | UI framework, rendering, widgets, platform channels | Runtime |
| `crypto` | ^3.0.7 | BSD-3-Clause | `package:crypto` from Dart SDK ecosystem | Cryptographic hash functions (SHA-256, SHA-512, HMAC) for content hashing, toolchain artifact verification, cache key derivation | Runtime |
| `cryptography` | ^2.9.0 | Apache-2.0 | `package:cryptography` from pub.dev | Cryptographic primitives for signature verification, key derivation, secure random generation used in toolchain provenance and secret handling | Runtime |
| `web` | ^1.1.1 | BSD-3-Clause | `package:web` from Dart SDK ecosystem | Web platform interop types for browser-virtual file system provider and web-hosted workspace route | Runtime (Web target only) |
| `cupertino_icons` | ^1.0.8 | MIT | `package:cupertino_icons` from pub.dev | iOS-style icon set for Cupertino-themed UI surfaces on iOS and macOS targets | Runtime (iOS/macOS) |
| `shared_preferences` | ^2.5.5 | BSD-3-Clause | `package:shared_preferences` from Flutter ecosystem | Platform-appropriate persistent key-value store for user settings, theme profile, session preferences | Runtime |
| `path_provider` | ^2.1.5 | BSD-3-Clause | `package:path_provider` from Flutter ecosystem | Platform-appropriate directory path resolution for local file system operations, cache directories, document directories | Runtime |

## Dev Dependencies

| Dependency | Version | License | Source Boundary | Usage Boundary | Classification |
|---|---|---|---|---|---|
| `flutter_test` (SDK) | Flutter SDK | BSD-3-Clause | Flutter test framework SDK | Widget tests, unit tests, integration tests | Dev |
| `flutter_lints` | ^5.0.0 | BSD-3-Clause | `package:flutter_lints` from Flutter ecosystem | Static analysis lint rules for Dart/Flutter code quality | Dev |

## Prototype Dependencies

| Dependency | Version | License | Source Boundary | Usage Boundary | Classification |
|---|---|---|---|---|---|
| `playwright-core` | prototype/package.json | Apache-2.0 | npm `playwright-core` | Prototype screenshot and browser automation tooling | Dev (prototype only) |

## Build / CI / Platform Toolchain Dependencies

| Dependency | Source | Classification |
|---|---|---|
| CMake | System / CI image | Build |
| PkgConfig | System / CI image | Build |
| Android Gradle | Android SDK / CI image | Build |
| Apple platform runner toolchains | macOS / Xcode | Build |
| GitHub Actions | GitHub-hosted runners | CI |
| Python standard library (3.13.x) | System / CI image | CI / Scripts |
| Bash | System | CI / Scripts |
| Node.js (24.x) | System / CI image | CI (prototype) |
| Flutter SDK (3.41.x) | System / CI image | Build |

## UI Assets

UI assets must remain covered by documented open-source asset evidence before promotion into product surfaces. Asset sources and licenses are tracked in `docs/assets/INDEX.md`.

## Policy Rules

1. **No commercial/paid/proprietary dependencies.** No dependency may require commercial authorization, paid licensing, subscription access, membership access, trial-only terms, proprietary-use approval, or private registry access.
2. **Pre-registration required.** Any future dependency must be listed here with its license evidence, source boundary, and usage boundary before it can pass audit.
3. **Prototype isolation.** Prototype-only dependencies must stay prototype-scoped and must not become product runtime requirements without this file being updated.
4. **SDK exceptions.** Flutter SDK and Dart SDK dependencies are granted blanket authorization as platform-provided SDK components.
5. **Gate enforcement.** The `scripts/dependency-policy-gate.py` script enforces that every `pubspec.yaml` dependency (excluding SDK deps) has a corresponding entry in this file.
6. **License evidence required.** Each non-SDK dependency must carry a recognized SPDX license identifier or explicit license evidence.
7. **Generated reports.** Generated reports and gate summaries must summarize dependency, UI asset, and license evidence without copying target repository source.
