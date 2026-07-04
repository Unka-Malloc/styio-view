# Technology And Component Inventory

**Purpose:** Define the required technology-stack, internal-component, open-source-component, and dependency-manifest inventory for `Vityo`.

**Last updated:** 2026-06-29

This document is the repository-local maintenance rule for the manifest inventory audited by `styio-audit`. The canonical audit module must list the same surfaces in `for-vityo/module.json`; if this document and the audit manifest diverge, the change is not closed.

## Required Inventory Fields

Every audit manifest for this repository must maintain these non-empty lists:

1. `technology_stack`
2. `internal_components`
3. `open_source_components`
4. `dependency_manifests`

Missing or stale lists are audit failures. They block license, commercial-risk, ownership, and usage-boundary review because auditors cannot prove what stack and components are in scope.

## Current Inventory

### Technology Stack

- Flutter and Dart frontend workspace.
- Android, iOS, macOS, Linux, Windows, and web platform runners.
- CMake native runner integration for desktop platforms.
- JavaScript, HTML, and CSS prototype with Playwright screenshot tooling.
- Python and Bash repository, docs, and device/profile scripts.
- GitHub Actions workflow automation.

### Internal Components

#### Editors, Runtimes, And IDE Surfaces

- Workspace document store, editor controller, selection, persistence, and shell state.
- Backend toolchain and integration adapters for local, hosted, and web execution routes.
- Module host, module manifests, capability matrices, staged updates, and platform visibility.
- Runtime replay surfaces, hosted payload codecs, debug console summaries, and graph/lane models.
- Prototype UI and development server security harness.

#### Security, Permission, And Audit Components

- **Agent permission model** (`agent_permission_model.dart`): Agent role definitions, capability enum, permission lattice, context minimizer, and provider capability profiles.
- **Tool permission system** (`agent_tool_permission.dart`): Permission decision engine, pattern-based rules, three-state action model (allow/ask/deny), audit records, and plan status tracking.
- **Sandboxed tool router** (`agent_tool_sandbox_router.dart`): Multi-layer tool call validation pipeline — permission plan, execution mode, capability checks, output size limits, and audit logging.
- **Tool call execution journal** (`agent_tool_call_execution_journal.dart`): Audit journal with replay support and sensitive-data redaction for tool call history.
- **Agent session permission model** (`agent_session.dart`): Permission request scopes, decision lifecycle, immutable audit events, and tool invocation tracking.
- **Execution sandbox** (`execution_sandbox.dart`): Local execution policy with workspace containment, path traversal/symlink detection, environment allowlisting, network policy, timeout, and output bounds.
- **Log redactor** (`log_redactor.dart`): Pattern-based and field-based credential redaction for all log, diagnostic, runtime, and agent-context output.
- **Secret store** (`secret_store.dart`): Credential reference lookup and local secret resolution.
- **Module manifest security** (`module_manifest_security.dart`): Module manifest trust validation — schema, signature, checksum, permission allowlist, engine compatibility, quarantine, and rollback.
- **Tool registry** (`agent_tool_registry.dart`): Tool definition registry with capability and permission-mode declarations.
- **Permission policy store** (`agent_tool_permission_policy_store.dart`): Permission policy persistence and override loading.

#### Governance And Security Scripts

- `check_security_baseline.py`: Required file existence and forbidden-pattern scan.
- `supply-chain-governance-gate.py`: CI/CD workflow permissions, Dependabot coverage, SBOM evidence, secret ignore baseline, high-signal secret scan.
- `dependency-policy-gate.py`: Dependency registration enforcement in `DEPENDENCY-USAGE.md`.
- `github-actions-pin-gate.py`: GitHub Actions SHA-pinning audit and enforcement.
- `check_license_policy.py`: Package license allowlist and forbidden license marker checks.
- `release-readiness-gate.py`: End-to-end release readiness validation.
- `repo-hygiene-gate.py`: Local development hygiene gate (credential scanning, secrets check).

#### Docs, Product, Device, And Delivery Gate Scripts

- Docs, product, device, and delivery gate scripts.

### Open-Source And External Components

- Flutter SDK and Dart SDK.
- `cupertino_icons`.
- `shared_preferences`.
- `path_provider`.
- `flutter_test`.
- `flutter_lints`.
- `crypto` (SHA-256/512 for module manifest checksums and signature verification).
- `playwright-core`.
- `PkgConfig`.
- Android Gradle and platform runner toolchains.
- Apple platform runner toolchains.
- GitHub Actions.

### Dependency Manifest Surfaces

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
