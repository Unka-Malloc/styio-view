# Vityo API Compatibility Policy

**Purpose:** Define Vityo's API compatibility rules across public models, adapter contracts, module manifests, and agent tool interfaces. This is the SSOT for what constitutes a breaking change and how compatibility is maintained.

**Owner:** Governance owner (`CODEOWNERS` → governance domain)
**Last updated:** 2026-06-24

---

## 1. Compatibility Scope

### 1.1 Public API Surfaces

The following are public API surfaces subject to compatibility rules:

| Surface | Location | Consumer |
|---------|----------|----------|
| Adapter contracts | `view_ide/backend_toolchain/`, `view_ide/language/contract/` | External adapters, language services |
| Module manifest schema | `view_ide/module_host/extension_manifest_contract.dart` | Extension developers |
| Agent tool interface | `view_ide/agent/agent_session.dart` | Agent tool developers |
| Workspace model | `view_ide/workspace/` | View render surfaces, external tooling |
| IDE capability registry | `view_ide/workbench/ide_capability_registry.dart` | Product gates, UI surfaces |
| Configuration schema | `view_ide/environment/configuration/` | Settings UI, bootstrap |
| Baseline JSON schema | `toolchain/vityo-ide-capability-baseline.json` | Product gates |

### 1.2 Internal Surfaces (Not Compatibility-Governed)

- `view_render/` internals (Flutter widgets, theme details)
- `app/` composition root internals
- `prototype/` web editor internals
- Test fixtures and mocks
- Script implementation details (public CLI flags are governed)

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

## 7. Test Requirements

### 7.1 Compatibility Tests

Every public model/contract must have:
- **Serialization round-trip test**: serialize → deserialize → serialize, verify equality
- **Unknown field tolerance test**: deserialize payload with extra fields, verify `extensions` preserved
- **Schema version test**: verify schemaVersion is present and valid
- **Capability negotiation test** (for adapter contracts): verify intersection logic

### 7.2 Gate Enforcement

- `scripts/architecture_boundary_gate_test.py` enforces import boundaries
- `scripts/ide-product-parity-gate.py` checks capability baseline coverage
- `scripts/vityo-ide-product-gate.py` checks product gate compliance

## 8. Cross-Reference

- [Vityo Protocol And Capability Negotiation](../design/Vityo-Protocol-And-Capability-Negotiation.md)
- [Vityo Extension And Contribution Model](../design/Vityo-Extension-And-Contribution-Model.md)
- [Security and Supply Chain](./SECURITY-AND-SUPPLY-CHAIN.md)
- [Architecture Runbook](../teams/ARCHITECTURE-RUNBOOK.md)
