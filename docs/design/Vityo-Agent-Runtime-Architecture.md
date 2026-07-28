# Vityo Agent Runtime Architecture

**Purpose:** Define Vityo's agent runtime architecture — how the agent core, provider routing, tool permission, patch workflow, and IDE surface are decoupled. Vityo's agent is IDE-integrated, not a standalone CLI agent.

**Owner:** Agent architecture owner (`CODEOWNERS` → agent domain)
**Last updated:** 2026-06-24

---

## 1. Architecture Overview

```
┌──────────────────────────────────────────────────────┐
│  view_render/agent/    Agent Surface (Flutter UI)     │
├──────────────────────────────────────────────────────┤
│  view_ide/agent/       Agent Domain Model             │
│  ┌──────────┬──────────┬───────────┬──────────────┐  │
│  │ Context  │ Provider │ Tool      │ Patch        │  │
│  │ Session  │ Route    │ Permission│ Transaction  │  │
│  │ Snapshot │ Registry │ Journal   │ Workspace    │  │
│  └──────────┴──────────┴───────────┴──────────────┘  │
├──────────────────────────────────────────────────────┤
│  agent/                Agent Core (no Flutter)        │
│  Provider Adapter | Tool Registry | Session Control │
└──────────────────────────────────────────────────────┘
```

## 2. Core Components

### 2.1 Agent Context (`agent_context.dart`)

The agent context is a snapshot of the IDE state at the moment of agent invocation:

```dart
class AgentContext {
  final int schemaVersion;
  final String contextId;
  final DateTime capturedAt;
  final WorkspaceSnapshot workspace;       // Open files, dirty state
  final DiagnosticSnapshot diagnostics;    // Current errors/warnings
  final RuntimeSnapshot runtime;           // Running processes, terminals
  final CommandCatalogSnapshot commands;   // Available commands
  final ContextScope scope;                // What's visible to the agent
  final RedactionPolicy redaction;         // What's redacted from context
}
```

**Scope levels:**
- `current-file` — only the active editor file
- `open-editors` — all open editor tabs
- `workspace` — the entire workspace
- `workspace-with-diagnostics` — workspace + diagnostic data
- `full` — workspace + diagnostics + runtime + commands

**Redaction policy:**
- `none` — no redaction
- `secrets` — redact detected secrets (API keys, tokens)
- `paths` — redact absolute file paths
- `strict` — redact secrets + paths + hostnames

### 2.2 Agent Settings (`agent_settings.dart`)

Provider configuration with credential safety:

```dart
class AgentSettings {
  final int schemaVersion;
  final String activeProviderId;
  final List<ProviderEndpoint> providers;
  final PermissionPolicy defaultPolicy;
  final int maxToolCallRounds;       // Safety limit
  final int contextWindowBudget;     // Token budget for context
  final Duration toolCallTimeout;
}

class ProviderEndpoint {
  final String id;
  final ProviderKind kind;           // local | remote | openai-compatible
  final String credentialRef;        // ENV_VAR name or secret reference, NEVER raw key
  final String? endpointUrl;         // For remote/OpenAI-compatible providers
  final bool requiresNetwork;
  final RetryPolicy retry;
}
```

**CRITICAL:** `credentialRef` stores only an environment variable name or secret store reference. Raw API keys MUST NOT be stored in settings files, shared preferences, or any persistence layer.

### 2.3 Agent Tools and Permission (`agent_tool_permission.dart`)

Permission levels (configurable, auditable, testable):

| Level | Description | Example Tools |
|-------|------------|---------------|
| `read-only` | Read files, search, inspect | `read_file`, `search`, `list_directory` |
| `workspace-write` | Modify workspace files | `edit_file`, `create_file`, `delete_file` |
| `toolchain` | Execute build/compile tools | `run_build`, `run_test` |
| `network` | Make network requests | `fetch_url`, `api_call` |
| `destructive` | Delete files outside workspace | `rm_external`, `git_reset_hard` |
| `open-world` | Unrestricted shell access | `shell_exec` |
| `full-access` | All permissions (admin only) | Reserved for explicit user approval |

**Permission policy store** (`agent_tool_permission_policy_store.dart`):
- Persists user-configured permission policies
- Supports per-tool, per-provider, and global defaults
- Audit log of all permission changes
- Testable: every policy mutation must have a test

### 2.4 Patch Workflow (`agent_code_patch_applier.dart`)

Agent proposes patches; workspace applies them through the edit transaction system:

```
1. Agent proposes patch (diff or full-file)
2. User previews patch in agent surface
3. User approves → patch applied via workspace edit transaction
4. Workspace records transaction in journal
5. User can rollback via journal replay
```

**Journal** (`agent_tool_call_execution_journal.dart`):
- Records every tool call with input, output, timestamp, and permission level
- Supports replay for audit
- Redacts sensitive data in display projection

### 2.5 Provider Routing

**Provider registry** (`agent_provider_registry.dart`):
- Registers available AI providers (local models, remote endpoints)
- Each provider has a health history store
- Providers declare their capabilities (max context, tool support, streaming)

**Route executor** (`agent_provider_route_executor.dart`):
- Routes agent requests to the appropriate provider
- Handles provider unavailability with fallback
- Records provider health events

## 3. Security Model

### 3.1 Credential Safety

1. **NEVER store raw API keys.** Only store env var names or secret references.
2. **Display projection must be redacted.** Any UI displaying settings must show `***` for credentials.
3. **Network transport** must use TLS for all remote providers.
4. **Provider health history** tracks authentication failures without logging credentials.

### 3.2 Permission Audit

1. Every tool call is journaled with permission level, timestamp, and outcome.
2. Permission elevation requires explicit user confirmation.
3. Tool calls with `destructive` or higher permission require confirmation unless pre-approved.
4. Permission policy changes are logged with timestamp and reason.

### 3.3 Context Safety

1. Context snapshots are scoped per `ContextScope` setting.
2. Redaction policy is applied before context is sent to provider.
3. Workspace snapshots exclude files matching `.gitignore` and custom exclusion patterns.
4. Diagnostic and runtime snapshots exclude security-sensitive data.

## 4. Agent Session Lifecycle

```
[create] → [context capture] → [provider route] → [tool loop]
                                                       ↓
                                              [patch preview]
                                                       ↓
                                              [user approve/reject]
                                                       ↓
                                              [apply / journal]
                                                       ↓
                                              [session complete]
```

### 4.1 Session Context (`agent_session_context.dart`)

Each session has:
- Unique session ID
- Creation timestamp
- Provider ID used
- Context scope at creation
- Tool call count and round count
- Completion status

### 4.2 Session History (`agent_coding_session_history_store.dart`)

Persists completed sessions for:
- User review
- Audit trail
- Context reuse (resume a previous session)

## 5. IDE Integration Boundaries

### 5.1 Agent DOES NOT

- Directly write files (must go through workspace edit adapter)
- Bypass the document model
- Access the file system directly
- Execute shell commands without tool permission
- Store raw API keys

### 5.2 Agent DOES

- Read workspace state through snapshot
- Propose edits through patch workflow
- Execute approved tools through tool dispatcher
- Route to configured providers
- Journal all actions for audit

## 6. Testing Requirements

| Component | Test File | Required Tests |
|-----------|----------|---------------|
| Agent Context | `agent_context_test.dart` | Serialization, scope, redaction |
| Agent Settings | `agent_settings_test.dart` | Credential safety, provider config |
| Tool Permission | `agent_tool_permission_test.dart` | Level check, elevation, audit |
| Permission Policy | `agent_tool_permission_policy_store_test.dart` | CRUD, audit log |
| Patch Transaction | `agent_code_patch_applier_test.dart` | Preview, apply, rollback |
| Provider Registry | `agent_provider_registry_test.dart` | Register, health, fallback |
| Session Context | `agent_session_context_test.dart` | Lifecycle, completion |

Every agent test must verify:
1. No raw API key in any serialized output
2. Redaction applied in display projections
3. Journal entry created for mutating operations

## 7. Cross-Reference

- [Vityo Mainstream Architecture Alignment](./Vityo-Mainstream-Architecture-Alignment.md)
- [Vityo Protocol And Capability Negotiation](./Vityo-Protocol-And-Capability-Negotiation.md)
- [Agent Runtime Runbook](../teams/AGENT-RUNTIME-RUNBOOK.md)
- [Security and Supply Chain](../governance/SECURITY-AND-SUPPLY-CHAIN.md)
- [API Compatibility](../governance/API-COMPATIBILITY.md)
