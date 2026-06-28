# Vityo Build And Dev Environment

**Purpose:** Provide the repository-level entry point for bootstrapping a fresh machine, installing shared GUI toolchains, and routing contributors to the correct implementation surface.

**Last updated:** 2026-06-28

## Who This Is For

1. Contributors bringing up `Vityo` on a fresh Debian/Ubuntu VM or container.
2. Contributors working on the Flutter shell in `frontend/vityo_app/`.
3. Contributors working on the handwritten web prototype in `prototype/`.
4. Contributors bringing up the native Windows desktop target without WSL or Docker.

## Fresh Machine Bootstrap

`Vityo` now ships both containerized and host-native environment entrypoints.

Flutter source lives under `frontend/vityo_app/`, and the Dart package is
`vityo_app`.

### Container / VM

Build and launch the standardized Linux developer container:

```bash
./scripts/bootstrap-dev-container.sh
```

Build the Linux + Android combo image:

```bash
./scripts/bootstrap-dev-container.sh --with-android
```

For editor-integrated devcontainers, open [../.devcontainer/devcontainer.json](../.devcontainer/devcontainer.json).

### Host Install Matrix

| Host | Base profile | Optional combos | Entry script |
|------|--------------|-----------------|--------------|
| Linux | `linux` desktop + `web` | `linux+android` | `./scripts/bootstrap-dev-env.sh [--with-android]` |
| macOS | `macos` desktop + `web` | `macos+ios`, `macos+android`, `macos+ios+android` | `./scripts/bootstrap-dev-env-macos.sh [--with-ios] [--with-android]` |
| Windows | `windows` desktop + `web` | `windows+android` | `powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap-dev-env-windows.ps1 [-WithAndroid]` |

All host scripts install the standardized toolchain, then call the shared workspace bootstrap entrypoint to restore `npm` / `flutter pub` dependencies and generate the selected Flutter runners. On Windows, `bootstrap-workspace.ps1` resolves `flutter.bat` / `npm.cmd` from `VITYO_FLUTTER_BIN`, `VITYO_FLUTTER_HOME`, `VITYO_NPM_BIN`, or `PATH`. It also preserves tracked Flutter metadata around runner generation and creates plugin junctions for the Windows runner when the host cannot create Flutter's default plugin symlinks.

Device verification stays host-driven:

1. Linux / Android verification uses the shell profile tools plus `verify-android-device.sh`.
2. Windows / Android verification uses the PowerShell profile tools plus `verify-android-device.ps1`.
3. macOS / iOS / macOS verification uses `apple-platform-profile.sh` plus `verify-apple-device.sh`.
4. The Linux container image is for shared desktop/Web/Android development and smoke builds; real mobile device verification still requires the corresponding host OS.

## Standardized Baseline

`Vityo` now follows the same shared project-level version discipline used by `styio-nightly` and `styio-spio` where the tool overlaps:

1. Development host standard: Debian `13` (`trixie`).
2. Compiler helper toolchain standard: LLVM / Clang `18.1.x` and CMake / CTest `3.31.6`.
3. Validation Python standard: `3.13.5`.
4. Node.js standard for prototype tooling: `v24.15.0` LTS.
5. Flutter / Dart standard: `3.41.7` / `3.11.5`.
6. Chromium standard for web verification: `147.0.7727.116`.
7. Android combo add-on standard is profile-driven on Linux, macOS, and Windows: command-line tools `14742923`, shared `platform-tools`, and the standardized profile set `android-35`, `android-36`, each with its own pinned platform/build-tools/NDK tuple from [../toolchain/android-sdk-profiles.csv](../toolchain/android-sdk-profiles.csv).
8. Apple build profiles on macOS are standardized in [../toolchain/apple-platform-profiles.csv](../toolchain/apple-platform-profiles.csv). These profiles pin iOS/macOS deployment targets and optionally select a specific `DEVELOPER_DIR` / Xcode installation.
9. CI mirror: GitHub Actions on `ubuntu-24.04` for the existing Linux/Web gates and `windows-latest` for PowerShell bootstrap, analyze, test, and native Windows build coverage, with exact Python, Node.js, Flutter, and Chromium version pins before validation steps.

## Required Toolchains

1. Flutter `3.41.7` with Dart `3.11.5` and the host desktop, Web, and optional Android targets enabled.
2. Android SDK command-line tools, platform tools, build tools, and NDK.
3. Chromium `147.0.7727.116` for local web verification.
4. Node.js `v24.15.0` LTS and npm for the handwritten prototype.
5. Python `3.13.5` for docs and repository hygiene scripts.
6. On macOS, full iOS add-on support also requires Xcode. The script can validate and wire it, but Apple-controlled Xcode installation may still require App Store or Apple developer authentication.
7. On Windows, native desktop builds require Visual Studio 2022 Build Tools with the C++ desktop workload. `bootstrap-dev-env-windows.ps1` installs this through `winget`; hosted `windows-latest` CI already includes the required build environment.

## Typical Build And Test Commands

Shared workspace bootstrap after the toolchain is present:

```bash
./scripts/bootstrap-workspace.sh --platforms web,linux
```

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap-workspace.ps1 -Platforms web,windows
```

Example combinations:

```bash
./scripts/bootstrap-workspace.sh --platforms web,linux,android
./scripts/bootstrap-workspace.sh --platforms web,macos,ios
./scripts/bootstrap-workspace.sh --platforms web,macos,android
```

Windows native desktop validation:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap-dev-env-windows.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap-workspace.ps1 -Platforms web,windows
Set-Location frontend\vityo_app
flutter pub get
flutter analyze
flutter test
flutter build windows --debug
```

Run the Windows validation commands from a regular PowerShell session. The bootstrap script restores the tracked `.metadata` and `pubspec.lock` files after Flutter writes generated state, and the plugin junction fallback avoids requiring Developer Mode or elevated symlink privileges for `flutter build windows --debug`.

Linux Android SDK profile management:

```bash
./scripts/android-sdk-profile.sh list
eval "$(./scripts/android-sdk-profile.sh env android-35)"
./scripts/android-sdk-profile.sh run android-36 -- bash -lc 'cd frontend/vityo_app && flutter build apk --debug'
./scripts/android-sdk-profile.sh build --profiles android-35,android-36 --parallel --artifact apk --mode debug
```

Linux host bootstrap can install multiple Android SDK profiles into the same SDK root:

```bash
./scripts/bootstrap-dev-env.sh --with-android --android-profiles android-35,android-36 --android-default-profile android-36
```

The Linux container path supports the same profile set:

```bash
./scripts/bootstrap-dev-container.sh --with-android --android-profiles android-35,android-36 --android-default-profile android-36
```

macOS profile management:

```bash
./scripts/bootstrap-dev-env-macos.sh --with-ios --with-android --android-profiles android-35,android-36 --android-default-profile android-36
./scripts/android-sdk-profile.sh list
./scripts/apple-platform-profile.sh list
eval "$(./scripts/android-sdk-profile.sh env android-35)"
eval "$(./scripts/apple-platform-profile.sh env ios-15)"
./scripts/apple-platform-profile.sh build --profiles ios-13,ios-15 --parallel --mode debug --simulator --no-codesign
./scripts/apple-platform-profile.sh build --profiles macos-10.15,macos-12 --parallel --mode debug
```

Windows Android SDK profile management:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap-dev-env-windows.ps1 -WithAndroid -AndroidProfiles android-35,android-36 -AndroidDefaultProfile android-36
powershell -ExecutionPolicy Bypass -File .\scripts\android-sdk-profile.ps1 list
powershell -ExecutionPolicy Bypass -File .\scripts\android-sdk-profile.ps1 env android-35
powershell -ExecutionPolicy Bypass -File .\scripts\android-sdk-profile.ps1 build --profiles android-35,android-36 --parallel --artifact apk --mode debug
```

Real-device verification entrypoints:

```bash
./scripts/verify-android-device.sh --profile android-36 --device-id <adb-device-id> --mode debug
./scripts/verify-apple-device.sh --profile ios-15 --device-id <flutter-ios-device-id> --mode debug
./scripts/verify-apple-device.sh --profile macos-12 --mode debug
```

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\verify-android-device.ps1 -Profile android-36 -DeviceId <adb-device-id> -Mode debug
```

Use the same profile family for bootstrap, build, and device verification. Do not mix `android-35` bootstrap with `android-36` device verification unless you are explicitly testing a cross-profile mismatch.

Flutter shell:

```bash
cd frontend/vityo_app
flutter analyze
flutter test
flutter build web
```

Windows Flutter shell:

```powershell
Set-Location frontend\vityo_app
flutter pub get
flutter analyze
flutter test
flutter build windows --debug
```

Focused editor local preview:

```bash
./scripts/serve-flutter-web-preview.sh
```

This is the preferred one-command browser startup path for local editor review. It starts `prototype/dev_server.py` on port `8080`, redirects `/` to `/editor`, and serves the canonical focused editor from `prototype/editor.html`. The legacy script name is kept for compatibility, but this path no longer builds or serves the Flutter integration shell as the default visible page.

Handwritten prototype:

```bash
cd prototype
npm ci
npm run selftest:editor
```

If you use the bundled `dev_server.py` directly, set the focused editor URL explicitly because the default server port is `4180`:

```bash
cd prototype
STYIO_EDITOR_URL=http://127.0.0.1:4180/editor npm run selftest:editor
```

Repository docs and hygiene checks:

```bash
./scripts/docs-gate.sh
python3 scripts/docs-index.py --write
python3 -m pytest tests/test_docs_tooling_coverage.py
python3 scripts/repo-hygiene-gate.py --mode tracked
./scripts/delivery-gate.sh --mode checkpoint --skip-health
```

IDE architecture, compatibility, sandbox/security, and performance budget checks:

```bash
python3 scripts/check_architecture_boundaries.py
python3 scripts/check_compat_facades.py
python3 scripts/check_security_baseline.py
python3 scripts/check_performance_budgets.py
git diff --check
```

`check_architecture_boundaries.py` enforces `view_ide/` as the Flutter-free domain/application layer and `view_render/` as the presentation layer. `check_compat_facades.py` keeps migrated legacy roots as one-line `export` facades. `check_security_baseline.py` protects sandbox execution, log redaction, secret storage, module manifest security, and agent permission modeling. `check_performance_budgets.py` verifies benchmark coverage for the performance-sensitive IDE paths.

When Dart or Flutter is available and the change touches editor data structures, language cache, workspace graph, runtime events, AI context packing, watchers, or UI virtualization, run the benchmark regression gate:

```bash
python3 scripts/performance-gate.py --threshold 1.10
```

Static release readiness without a release build:

```bash
python3 scripts/release-readiness-gate.py --skip-build
```

Full checkpoint delivery floor:

```bash
./scripts/delivery-gate.sh --mode checkpoint
```

## Subsystem-Specific Follow-Ups

1. Flutter shell details: [../frontend/vityo_app/README.md](../frontend/vityo_app/README.md)
2. Handwritten prototype details: [../prototype/README.md](../prototype/README.md)
3. Product and system design: [design/Vityo-System-Architecture.md](./design/Vityo-System-Architecture.md)
4. Team and review routing: [teams/COORDINATION-RUNBOOK.md](./teams/COORDINATION-RUNBOOK.md)
5. Host-local Windows workspace bootstrap: [../scripts/bootstrap-workspace.ps1](../scripts/bootstrap-workspace.ps1)
6. Contribution workflow: [../CONTRIBUTING.md](../CONTRIBUTING.md)
7. Release checklist: [governance/RELEASE-CHECKLIST.md](./governance/RELEASE-CHECKLIST.md)

## Related Docs

1. Docs tree guide: [README.md](./README.md)
2. Product spec: [design/Vityo-Product-Spec.md](./design/Vityo-Product-Spec.md)
3. Handwritten Web IDE handbook: [specs/HANDWRITTEN-WEB-IDE-ENGINEERING-HANDBOOK.md](./specs/HANDWRITTEN-WEB-IDE-ENGINEERING-HANDBOOK.md)
