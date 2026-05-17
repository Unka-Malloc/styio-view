# Service Layer

**Purpose:** Document the `docs/design/service/` collection scope, ownership, and maintenance rules.
**Last updated:** 2026-05-17

Service Layer only exposes directories that can provide callable services to upper layers.

A top-level Service Layer directory must represent a service provider that can be consumed by Interaction, Appearance, or app-shell surfaces. Connectors, adapters, caches, fixture matrices, protocol helpers, and quality gates are internal implementation details of a concrete service and must not appear as root Service Layer modules.

## 1. Directory Rule

```text
docs/design/service/
  README.md
  styio-language-service/
    README.md
    styio-service-connector/                 # internal
    styio-result-adapter/                    # internal
    language-result-cache/                   # internal
    language-fixture-confidence-matrix/      # internal quality/design support
  user-service/
    README.md
```

Corresponding implementation target:

```text
frontend/vityo_app/lib/src/view_ide/service/
  styio_language_service/
    connector/
    adapter/
    result_cache/
    fixture_confidence/
  user_service/
    local_profile/
    optional_login/
    profile_sync_adapter/
    session_state/
```

## 2. Top-Level Services

| Service directory | Direct upper-layer service | Notes |
|---|---|---|
| `styio-language-service/` | Syntax validation, diagnostics, completion, hover, semantic tokens, definition/references, rename facts, code actions, and language snapshots. | Styio owns language truth; Vityo owns service connection, binding, adaptation, freshness, and product consumption. |
| `user-service/` | Local profile, optional login, optional profile sync, account/session status, and privacy boundary status. | Optional service. Local IDE use must work without login or cloud sync. |

## 3. Disallowed Root Directories

| Root directory type | Correct placement |
|---|---|
| `*-connector/` | Internal to the concrete service that connects to an external or local provider. |
| `*-adapter/` | Internal to the concrete service that adapts provider results into Vityo facts. |
| `*-cache/` | Internal to the service or owning horizontal layer that owns the cached result. |
| `*-fixture-*` | Internal quality/design support under the service it validates. |
| `*-contract/` | Lives in the horizontal layer that owns the contract truth. |
| `*-consumer/` | Usually belongs to the upper layer consuming service results, not the Service Layer root. |

## 4. Boundary

Service Layer does not render UI, own editor commands, own file-system primitives, or define Styio language truth.

| Capability | Owner |
|---|---|
| UI rendering and app shell surfaces | Appearance Layer |
| Commands, controller state, editor behavior | Interaction Layer |
| File system, DataStore, platform context, execution, configuration, toolchain | Environment Layer |
| Styio grammar, parser, semantics, and language facts | StyioService / Styio toolchain |
