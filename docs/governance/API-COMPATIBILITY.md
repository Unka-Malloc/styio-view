# Vityo API Compatibility Policy

**Purpose:** Define Vityo's API compatibility rules across public models, adapter contracts, module manifests, and agent tool interfaces. This is the SSOT for what constitutes a breaking change and how compatibility is maintained.

**Owner:** Governance owner (`CODEOWNERS` → governance domain)
**Last updated:** 2026-06-25

---

## 1. Compatibility Scope

### 1.1 Public API Surfaces

The following are public API surfaces subject to compatibility rules:

| Surface | Location | Consumer |
|---------|----------|----------|
| Adapter contracts | `view_ide/backend_toolchain/`, `view_ide/language/contract/` | External adapters, language services |
| Module manifest schema | `view_ide/module_host/extension_manifest_contract.dart` | Extension developers |
| Agent tool interface | `view_ide/agent/agent_session.dart` | Agent tool developers |
| Agent permission model | `view_ide/agent/agent_permission_model.dart` | Agent tools, sandbox routing |
| Workspace model | `view_ide/workspace/` | View render surfaces, external tooling |
| IDE capability registry | `view_ide/workbench/ide_capability_registry.dart` | Product gates, UI surfaces |
| Configuration schema | `view_ide/environment/configuration/` | Settings UI, bootstrap |
| Security-sensitive environment contracts | `view_ide/environment/execution/`, `view_ide/environment/configuration/secret_store.dart` | Execution sandbox, local settings |
| Baseline JSON schema | `toolchain/vityo-ide-capability-baseline.json` | Product gates |

### 1.2 Internal Surfaces (Not Compatibility-Governed)

- `view_render/` internals (Flutter widgets, theme details)
- `app/` composition root internals
- `prototype/` web editor internals
- Test fixtures and mocks
- Script implementation details, except public CLI flags and gate outputs

## 2. Schema Versioning Rules

### 2.1 Every Public Model MUST Have schemaVersion

```dart
class MyContract {
  final int schemaVersion;  // REQUIRED for all public models
  // ...
}
```

### 2.2 Version Bump Rules

| Change | Version Bump | Breaking? |
|--------|-------------|-----------|
| Add optional field | Minor (1.0 → 1.1) | No |
| Add enum value | Minor (1.0 → 1.1) | No |
| Add capability flag | Minor (1.0 → 1.1) | No |
| Remove field | Major (1.x → 2.0) | YES |
| Change field type | Major (1.x → 2.0) | YES |
| Remove enum value | Major (1.x → 2.0) | YES |
| Change field semantics | Major (1.x → 2.0) | YES |
| Add required field | Major (1.x → 2.0) | YES |

### 2.3 Unknown Field Tolerance

All decoders MUST preserve unknown fields (see [Vityo Protocol And Capability Negotiation](../design/Vityo-Protocol-And-Capability-Negotiation.md)).

## 3. Deprecation Policy

### 3.1 Deprecation Lifecycle

```
[stable] → [deprecated] → [removed]
   │            │              │
   │   min 1 minor release     │
   │            │   min 1 major release after deprecation
   └────────────┴──────────────┘
```

### 3.2 Deprecation Annotation

Deprecated APIs must be annotated:

```dart
/// @deprecated Since v1.2. Use [newMethod] instead.
/// Will be removed in v3.0.
@Deprecated('Use newMethod instead')
void oldMethod();
```

### 3.3 Breaking Change Notification

Breaking changes require:
1. ADR documenting the change rationale
2. Migration guide for consumers
3. Major version bump
4. Release notes entry

### 3.4 Deprecation Record

Every public deprecation must name:

1. Deprecated symbol, path, schema field, manifest field, or command flag.
2. Replacement path and minimum compatible version.
3. Earliest removal target.
4. Required test or gate that proves the replacement works.
5. Whether a compatibility facade remains and when it can be deleted.

## 4. Adapter Contract Compatibility

### 4.1 Forward Compatibility

Adapters MUST tolerate:
- Unknown fields in payloads (store in `extensions` map)
- New capability flags (treat as `false` if unknown)
- New enum values (treat as unknown/fallback)

### 4.2 Backward Compatibility

Adapters SHOULD:
- Accept older schema versions (negotiate capability intersection)
- Provide default values for new optional fields
- Not require newly-added capability flags

### 4.3 Capability Negotiation

The effective capability set is the intersection of what both sides support. See [Vityo Protocol And Capability Negotiation](../design/Vityo-Protocol-And-Capability-Negotiation.md).

## 4.4 Compatibility Facade Policy

Legacy import roots exist only to keep migrated callers compiling while they move to the new IDE architecture:

| Legacy root | Allowed target root | Rule |
|-------------|---------------------|------|
| `frontend/vityo_app/lib/src/backend_toolchain/` | `view_ide/backend_toolchain/` | One-line `export` only |
| `frontend/vityo_app/lib/src/editor/` | `view_ide/editor/` or `view_render/editor/` | One-line `export` only for migrated entries |
| `frontend/vityo_app/lib/src/language/` | `view_ide/language/` | One-line `export` only |

Facades must not contain parsers, adapters, state, feature flags, fallback logic, security policy, or UI code. New logic belongs in the owning `view_ide/` or `view_render/` surface. The enforcement command is:

```bash
python3 scripts/check_compat_facades.py
```

Migration rule:

1. Keep the facade while downstream imports still exist.
2. Move implementation to the owner surface.
3. Update tests and docs to name the owner surface, not the facade.
4. Remove the facade only in a documented breaking release or after all supported imports have migrated.

## 5. Module Manifest Compatibility

### 5.1 Manifest Schema Evolution

- `schemaVersion` in `extension_manifest_contract.dart` governs compatibility.
- New optional fields in manifests are forward-compatible.
- Old manifests with lower `schemaVersion` must be accepted by newer hosts.
- Manifest validation must not reject manifests with unknown fields.

### 5.2 Contribution Point Evolution

- New contribution point types can be added at any time.
- Existing contribution point types cannot change their required fields.
- Contribution point removal requires a major version bump.

## 6. Agent Tool Compatibility

### 6.1 Tool Interface

- Tool names are stable identifiers; renaming a tool is a breaking change.
- Tool parameter additions (optional) are non-breaking.
- Tool parameter removals or type changes are breaking.
- Tool permission level changes (more restrictive) are breaking.

### 6.2 Permission Model Evolution

- New permission levels can be added (non-breaking).
- Existing permission level semantics cannot change without a major version bump.
- Permission level removal requires a major version bump.

### 6.3 Sandbox And Permission Migration

`agent_permission_model.dart` is a public compatibility surface because module-contributed tools and provider routes depend on it. Changes that increase required permission, change default approval, or move a tool into a stricter sandbox are compatibility-affecting even when the Dart type signature does not change.

Required migration evidence:

1. Existing tool declarations still deserialize.
2. Unknown permission values fail closed or downgrade to a documented safe default.
3. User-facing approval text and journal records remain stable enough for audit.
4. `python3 scripts/check_security_baseline.py` passes.

## 7. Test Requirements

### 7.1 Compatibility Tests

Every public model/contract must have:
- **Serialization round-trip test**: serialize → deserialize → serialize, verify equality
- **Unknown field tolerance test**: deserialize payload with extra fields, verify `extensions` preserved
- **Schema version test**: verify schemaVersion is present and valid
- **Capability negotiation test** (for adapter contracts): verify intersection logic

### 7.2 Gate Enforcement

- `scripts/check_architecture_boundaries.py` enforces resolved `view_ide` / `view_render` import boundaries
- `scripts/check_compat_facades.py` enforces one-line legacy compatibility facades
- `scripts/check_security_baseline.py` enforces required sandbox, redaction, secret, manifest-security, and agent-permission files
- `scripts/check_performance_budgets.py` enforces benchmark coverage markers for performance-sensitive paths
- `scripts/ide-product-parity-gate.py` checks capability baseline coverage
- `scripts/vityo-ide-product-gate.py` checks product gate compliance

## 8. Release And PR Checklist

Compatibility-affecting PRs must update [RELEASE-CHECKLIST.md](./RELEASE-CHECKLIST.md) evidence when they change a gate, deprecation window, migration rule, or release-readiness command.

## 9. Cross-Reference

- [Vityo Protocol And Capability Negotiation](../design/Vityo-Protocol-And-Capability-Negotiation.md)
- [Vityo Extension And Contribution Model](../design/Vityo-Extension-And-Contribution-Model.md)
- [Security and Supply Chain](./SECURITY-AND-SUPPLY-CHAIN.md)
- [Release Checklist](./RELEASE-CHECKLIST.md)
- [Architecture Runbook](../teams/ARCHITECTURE-RUNBOOK.md)
