# Vityo Protocol and Capability Negotiation

**Purpose:** Define Vityo's schema for versioned protocol contracts, capability negotiation, and backward-compatible evolution across all adapter boundaries. Inspired by LSP/DAP capability exchange but Styio-native.

**Owner:** Adapter contracts owner (`CODEOWNERS` → adapter-contracts domain)
**Last updated:** 2026-06-24

---

## 1. Design Principles

1. **Every contract has a schema version.** No implicit or unversioned protocols.
2. **Capability negotiation is explicit.** Both sides declare capabilities; the intersection determines behavior.
3. **Unknown fields are tolerated.** Decoders must not fail on unknown fields — forward compatibility is required.
4. **Blocked reasons are surfaced.** When a capability is unavailable, the reason must be machine-readable.
5. **Revisions are tracked.** Every payload carries a source revision or snapshot ID for staleness detection.

## 2. Universal Contract Schema

Every Vityo adapter contract conforms to this envelope:

```dart
class VersionedContract {
  final int schemaVersion;           // Contract schema version (monotonic)
  final Map<String, bool> capabilities;  // Capability flags
  final String? sourceRevision;      // Source revision or snapshot ID
  final Map<String, dynamic> extensions;  // Unknown field tolerance bucket
}
```

### 2.1 Schema Version Rules

1. **Major version bump** (e.g., 1 → 2): Breaking changes to required fields.
2. **Minor version bump** (e.g., 1.0 → 1.1): New optional fields added.
3. **Patch version bump** (e.g., 1.0.0 → 1.0.1): Documentation or validation changes only.

### 2.2 Capability Negotiation

Each contract declares a set of capability flags. The effective capability set is the **intersection** of what the client requests and what the server supports.

```dart
class CapabilityNegotiation {
  final Map<String, CapabilityStatus> requested;
  final Map<String, CapabilityStatus> resolved;
  final List<BlockedCapability> blocked;  // Capabilities that couldn't be satisfied
}

class CapabilityStatus {
  final bool supported;
  final String? version;            // Optional version of the capability
  final String? degradedReason;     // Why it's degraded (if supported but limited)
}

class BlockedCapability {
  final String capability;
  final String reason;              // Machine-readable reason code
  final String message;             // Human-readable explanation
}
```

## 3. Adapter Contracts

### 3.1 LanguageServiceAdapter

```dart
class LanguageServiceContract {
  final int schemaVersion;
  final Map<String, bool> capabilities;  // hover, completion, definition, references, rename, etc.
  final String languageId;
  final String sourceRevision;
  final Map<String, dynamic> extensions;
}
```

Reference: `frontend/vityo_app/lib/src/view_ide/language/contract/language_contract.dart`

### 3.2 ProjectGraphAdapter

```dart
class ProjectGraphContract {
  final int schemaVersion;
  final Map<String, bool> capabilities;  // dependency-graph, module-map, build-targets
  final String projectRoot;
  final String sourceRevision;
  final Map<String, dynamic> extensions;
}
```

Reference: `frontend/vityo_app/lib/src/view_ide/backend_toolchain/project_graph_contract.dart`

### 3.3 ExecutionAdapter

```dart
class ExecutionContract {
  final int schemaVersion;
  final Map<String, bool> capabilities;  // compile, run, test, debug
  final String targetId;
  final String sourceRevision;
  final Map<String, dynamic> extensions;
}
```

Reference: `frontend/vityo_app/lib/src/view_ide/backend_toolchain/execution_adapter.dart`

### 3.4 RuntimeEventAdapter

```dart
class RuntimeEventContract {
  final int schemaVersion;
  final Map<String, bool> capabilities;  // stdout, stderr, exit-code, signal, progress
  final String executionId;
  final String sourceRevision;
  final Map<String, dynamic> extensions;
}
```

Reference: `frontend/vityo_app/lib/src/view_ide/backend_toolchain/runtime_event_adapter.dart`

### 3.5 DebugWorkbenchContract

```dart
class DebugWorkbenchContract {
  final int schemaVersion;
  final Map<String, bool> capabilities;  // launch, attach, breakpoint, step, evaluate, output
  final String adapterId;
  final String sourceRevision;
  final DebugSessionLifecycle lifecycle;
  final Map<String, dynamic> extensions;
}

enum DebugSessionLifecycle { idle, launching, attaching, running, paused, terminated, detached }
```

Reference: `frontend/vityo_app/lib/src/view_ide/runtime/debug_workbench_contract.dart`

### 3.6 AgentProviderAdapter

```dart
class AgentProviderContract {
  final int schemaVersion;
  final Map<String, bool> capabilities;  // completion, chat, tool-use, streaming, vision
  final String providerId;
  final String sourceRevision;       // Provider version or model ID
  final Map<String, dynamic> extensions;
}
```

### 3.7 SourceControlAdapter

```dart
class SourceControlContract {
  final int schemaVersion;
  final Map<String, bool> capabilities;  // status, diff, commit, branch, push, pull
  final String branchIdentity;
  final String sourceRevision;       // HEAD commit hash
  final bool workspaceDirty;
  final Map<String, dynamic> extensions;
}
```

Reference: `frontend/vityo_app/lib/src/view_ide/workspace/source_control_adapter.dart`

## 4. Unknown Field Tolerance

All contract decoders MUST follow these rules:

1. When decoding, unknown JSON keys are stored in the `extensions` map, never discarded.
2. When re-encoding, the `extensions` map is serialized alongside known fields.
3. This ensures that a newer producer → older consumer → newer producer round-trip preserves all data.

**Test requirement:** Every adapter payload MUST have a test that:
1. Serializes a payload with extra unknown fields
2. Deserializes and verifies the unknown fields are preserved in `extensions`
3. Re-serializes and verifies the unknown fields are present in output

## 5. Stale Revision Detection

Every contract payload carries a `sourceRevision`:

- For language services: the document version or content hash
- For project graphs: the workspace state hash
- For execution: the execution ID
- For debug: the debug session ID
- For source control: the HEAD commit hash

**Rule:** If a consumer receives a payload with a `sourceRevision` older than the last processed revision, it MUST treat the payload as stale and either:
1. Request a fresh payload, or
2. Apply the payload with a staleness warning

## 6. Degraded and Blocked Capabilities

### 6.1 Degraded Capability

A capability is **degraded** when it is supported but with limitations:

```dart
{
  "capability": "completion",
  "supported": true,
  "degradedReason": "completion-limited-to-100-tokens"
}
```

### 6.2 Blocked Capability

A capability is **blocked** when it cannot be satisfied:

```dart
{
  "capability": "debug-attach",
  "reason": "no-debug-adapter-available",
  "message": "No debug adapter is configured for this language."
}
```

Blocked reasons are machine-readable codes, not free-form text. Standard codes:

| Code | Meaning |
|------|---------|
| `no-adapter` | No adapter registered for this capability |
| `no-provider` | No provider configured |
| `no-network` | Network unavailable |
| `no-toolchain` | Required toolchain not installed |
| `no-permission` | User has not granted permission |
| `unsupported-platform` | Platform does not support this capability |
| `feature-flag-disabled` | Feature flag is off |
| `stale-revision` | Source revision is too old |

## 7. Backward Compatibility Rules

1. **New optional fields are always allowed.** Older consumers ignore them.
2. **Required fields cannot be removed** without a major schema version bump.
3. **Field types cannot change** without a major schema version bump.
4. **Enum values can be added** but existing values cannot be removed or renumbered.
5. **Capability flags can be added** at any time; removing a flag requires a minor version bump.
6. **All decoders must accept and preserve unknown fields.**

## 8. Testing Requirements

| Test | Coverage |
|------|----------|
| `protocol_capability_negotiation_test.dart` | Capability intersection, blocked reasons, degraded capabilities |
| `debug_workbench_contract_test.dart` | Debug contract serialization, lifecycle states, capability negotiation |
| `source_control_adapter_test.dart` | SC contract, dirty workspace detection, branch identity |
| Per-contract serialization tests | Unknown fields, stale revision, backward compat |

Every adapter contract test must verify:
1. Schema version is present and parseable
2. Capabilities map is non-null
3. Unknown fields are preserved in `extensions`
4. Blocked reasons use standard codes
5. Stale revision is detectable

## 9. Cross-Reference

- [Vityo Mainstream Architecture Alignment](./Vityo-Mainstream-Architecture-Alignment.md)
- [Vityo Extension And Contribution Model](./Vityo-Extension-And-Contribution-Model.md)
- [Vityo Agent Runtime Architecture](./Vityo-Agent-Runtime-Architecture.md)
- [Adapter Contracts Runbook](../teams/ADAPTER-CONTRACTS-RUNBOOK.md)
- [LSP 3.17 Specification](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/) (reference only)
- [DAP Specification](https://microsoft.github.io/debug-adapter-protocol/specification) (reference only)
