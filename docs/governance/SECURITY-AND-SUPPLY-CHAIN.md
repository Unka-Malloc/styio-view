# Vityo Security and Supply Chain Policy

**Purpose:** Define security and supply-chain rules across the Vityo IDE, the shared Agent protocol, and compatible Agent runtimes.

**Owner:** Governance owner (`CODEOWNERS` → governance domain)
**Last updated:** 2026-07-30

---

## 1. Credential Safety

### 1.1 Rule: No Raw API Keys in Storage

**CRITICAL:** Raw API keys, tokens, passwords, or other credentials MUST NOT be stored in:

- Source code files
- Configuration files (`.json`, `.yaml`, `.env` committed to repo)
- Shared preferences or local storage without encryption
- Agent settings files
- Test fixtures (use placeholder values)

### 1.2 Credential References

Instead of raw values, use **credential references**:

```dart
class ProviderEndpoint {
  final String credentialRef;  // ENV_VAR name: "STYIO_API_KEY"
                                // or an opaque secret-store reference
  // NEVER: final String apiKey; → FORBIDDEN
}
```

### 1.3 Display Redaction

All UI surfaces that display settings or context MUST redact:
- Environment variable values → `[REDACTED]`
- API key references → `[SECRET]`
- Home directory paths → `$HOME/...`
- User-specific paths → `[USER_PATH]/...`

Reference implementations include `log_redactor.dart`, `secret_store.dart`, and the Agent context
projection code. Any IDE display surface must use a redacted protocol projection. Model/provider
configuration and credentials belong to the Agent runtime and must not be copied into IDE-owned
profiles or workspace state.

## 2. Agent Permission Boundaries

### 2.0 Ownership

The security boundary follows [ADR-0019](../adr/ADR-0019-vityo-is-the-styio-agent-native-ide.md):

1. The Agent runtime owns model/provider credentials, tool catalogs and execution, policy
   evaluation, permission-grant persistence, durable session journals, and multi-Agent delegation.
2. Vityo owns the workspace root and revision, context-export scope, permission-request
   presentation, the user's decision, change preview, and workspace transaction enforcement.
3. `packages/vityo_agent_protocol` carries requests, decisions, proposals, events, and receipts.
   It does not confer direct workspace access.
4. Existing IDE-side provider, tool-loop, policy, and journal files are migration-only
   implementation anchors. They remain governed until the atomic code migration removes them, but
   they do not define target ownership.

### 2.1 Permission Levels

| Level | Scope | Default Policy |
|-------|-------|---------------|
| `readOnly` | Read files, search, inspect | Allowed without confirmation |
| `workspaceWrite` | Modify workspace files | Confirmation required per session |
| `toolchainManaged` | Execute build/compile/test tools | Confirmation required per command |
| `fullAccessDisabledByDefault` | All permissions | Disabled by default; admin-only |

### 2.2 Permission Audit

Every tool call must:
1. Record permission level in journal
2. Log timestamp and outcome
3. Support replay for audit

Permission elevation requires explicit user confirmation with clear reason display.

### 2.3 Network Safety

- Agent-runtime provider connections must use TLS.
- Agent-runtime tool calls requiring network must declare `network` scope.
- Network requests from Agent tools are subject to timeout and rate limiting.
- Vityo must not make model-provider network requests.

### 2.4 Permission Model File

The stable boundary is the shared protocol permission request/decision plus Vityo's IDE-side
presentation. `products/vityo_app/lib/src/view_ide/agent_client/agent_permission_model.dart` is a
currently governed compatibility anchor while runtime policy moves to
`products/vityo_coding_agent/lib/src/policy/`. Changes to request scope, ordering, default
presentation, or approval text require compatibility and security review.

Required evidence:

1. Existing tool declarations still parse.
2. Unknown or malformed permission values fail closed.
3. Permission elevation is journaled.
4. Displayed context is redacted before it reaches the agent surface.

### 2.5 Agent Role Policy And Permission Lattice

The current IDE compatibility anchor `agent_permission_model.dart` defines:
- `AgentRole` enum: `build`, `plan`, `general`, `explore`, `scout`, `review`
- `AgentCapability` enum: `fileRead`, `fileWrite`, `processExec`, `network`, `secretAccess`, `moduleInstall`, `cloudUpload`, `terminalInteractive`
- `AgentPermissionLattice`: child agent permissions must be a subset of parent permissions; privilege escalation across roles is denied with structured `AgentSpawnPolicyDecision`.
- `AgentContextMinimizer`: context uploaded to providers is redacted and size-limited; secrets are excluded by default (`includeSecrets: false`), enforced by `LogRedactor` integration.

Changes to the role definitions, capability enum, or lattice derivation must preserve:
1. Unknown or unregistered roles return the empty permission set (fail closed).
2. Child agents cannot acquire capabilities the parent does not have.
3. Privileged capabilities (`secretAccess`, `moduleInstall`, `cloudUpload`, `terminalInteractive`) are never granted by default role policies.
4. Review role is strictly read-only and single-capability; any additional capability changes the role semantics.

### 2.6 Tool Permission System

Agent runtime policy is owned by
`products/vityo_coding_agent/lib/src/policy/policy_evaluator.dart` and
`permission_grant_store.dart`. The current IDE-side
`products/vityo_app/lib/src/view_ide/agent_client/agent_tool_permission.dart` remains governed as a
migration-only duplicate until it is removed atomically. Governed invariants:

1. **Three action states**: `allow`, `ask`, `deny` — every tool maps to exactly one.
2. **Pattern-based rules**: `AgentToolPermissionRule` with priority ordering and wildcard (`*`) matching. Higher-priority rules override lower-priority.
3. **Decision provenance**: Each decision records `source` (`tool-default` or `permission-rule`) and the matched `ruleId`.
4. **Destructive / open-world / network escalation**: Even tools with `permissionMode: never` (auto-allow) escalate to `ask` if they carry `destructive`, `openWorld`, or `network` capabilities.
5. **Plan statuses**: `ready` (all allowed), `reviewRequired` (some require review), `blocked` (some denied). The plan exposes `allowedToolIds`, `reviewToolIds`, `deniedToolIds`, `blockingIssueCodes`, and `recoveryActions`.
6. **Audit trail**: `AgentToolPermissionAuditRecord` captures tool ID, action, decision status, reason, rule ID, and creation timestamp for every decision.
7. **Unknown tools**: The sandbox router denies tools not present in the permission plan (deny-by-default for unregistered tools).

See also `agent_tool_permission_policy_store.dart` (permission policy persistence and override loading) and `agent_tool_registry.dart` (tool definition registry with capability declarations).

### 2.7 Sandbox Router

Agent tool execution is owned by
`products/vityo_coding_agent/lib/src/tools/tool_executor.dart`. The current IDE-side
`products/vityo_app/lib/src/view_ide/agent_client/agent_tool_sandbox_router.dart` remains governed
as a migration-only duplicate. Governed invariants:

1. **All agent tool calls route through this sandboxed router** — no direct transport bypass.
2. **Multi-layer validation**: permission plan → execution mode → capabilities → output size.
3. **Sensitive capabilities** (`destructive`, `network`, `openWorld`, `runtime.shell`, `build`, `workspace.patch.apply`, `ide.command`) are logged and audited.
4. **Execution mode enforcement**: plan-only mode blocks side-effect tools and IDE commands; build-capable mode allows build tools.
5. **Output size limits**: results exceeding `maxOutputLength` (100,000 chars) are truncated with metadata recording original length.
6. **Audit log**: every tool call outcome is appended to `_auditLog` when `auditEnabled` is true (default).
7. **Unknown tools are denied** with a structured rejection reason.

### 2.8 Execution Journal And Replay

Durable Agent journals and effect receipts are owned by
`products/vityo_coding_agent/lib/src/sessions/`. The current IDE-side
`agent_tool_call_execution_journal.dart` remains a migration-only audit anchor. Governed
invariants:

1. Every tool call produces an `AgentToolCallExecutionJournalEntry` with call ID, tool ID, status, input sample, result sample, error message, permission reason, execution status, permission status, review decision status, issue codes, and event count.
2. Journal entries support **replay**: `toReplayRequest()` produces a dispatch request with `replayedFromJournal: true` metadata.
3. **Sensitive data redaction**: Journal data is redacted through `_redactAgentToolJournalData`, which recursively checks for sensitive key patterns (`authorization`, `bearer`, `credential`, `password`, `token`, `apikey`, `secret`, `privatekey`, `accesskey`, `refreshtoken`) and redacts matching values to `[redacted]`.
4. **Replay plan and report**: `AgentToolCallReplayPlan` selects replay candidates; `AgentToolCallReplayReport` captures replay status, results, and events.

### 2.9 Permission Decision Scope Within Agent Sessions

The Agent runtime owns durable session state. The current IDE-side
`products/vityo_app/lib/src/view_ide/agent_client/agent_session.dart` defines a compatibility
projection used by the Workbench while protocol-backed projections replace it:
- `PermissionRequestScope`: `readOnly`, `workspaceWrite`, `toolchainManaged`, `fullAccessDisabledByDefault` — sequenced from least to most permissive (7 total scopes).
- `PermissionDecision`: `pending`, `allowOnce`, `allowForSession`, `deny`, `cancel`.
- `AgentAuditEventKind`: `sessionCreated`, `toolRequested`, `permissionRequested`, `permissionDecided`, `patchPreviewed`, `patchApplied`.
- `AgentSession`: immutable session state with turn history, tool invocations, permission requests, and audit events. `appendAuditEvent` and `copyWith` preserve immutability.

Changes to permission scope ordering, decision values, or audit event kinds must preserve:
1. `fullAccessDisabledByDefault` is never implicitly allowed; it requires explicit decision.
2. `readOnly` does not require elevation for allow.
3. All session mutations are immutable — no in-place state changes.

## 3. Dependency Provenance

### 3.0 Automated Update Coverage

Dependabot is configured in `.github/dependabot.yml` for:

- GitHub Actions workflows at `/`
- Flutter/Dart `pub` dependencies at `/products/vityo_app`
- npm prototype dependencies at `/prototype`

Dependabot PRs are review inputs, not automatic policy approval. Dependency additions still require `DEPENDENCY-USAGE.md` license/source/usage evidence before merge.

### 3.1 Flutter/Dart Dependencies

- All `pubspec.yaml` dependencies must be from `pub.dev` or verified Git sources.
- `pubspec.lock` must be committed and reviewed on dependency changes.
- `flutter pub outdated` should be run periodically; critical security updates applied promptly.

### 3.2 Node.js Dependencies (Prototype)

- All `package.json` dependencies must be from npm registry with verified integrity hashes.
- `package-lock.json` must be committed.
- `npm audit` must pass without critical/high findings in CI.

### 3.3 Python Dependencies (Scripts)

- Python scripts should use only stdlib or widely-trusted packages.
- If third-party packages are needed, they must be declared with pinned versions.

### 3.4 Dependency Registration Gate

`scripts/dependency-policy-gate.py` enforces that every dependency declared in `pubspec.yaml` (dependencies and dev_dependencies) and `prototype/package.json` (dependencies, devDependencies, optionalDependencies, peerDependencies) is registered in `DEPENDENCY-USAGE.md`. SDK dependencies (`flutter`, `flutter_test`, `dart`, `meta`, etc.) are exempt without explicit registration. The gate exits non-zero when unregistered dependencies are found.

CI must wire this gate through `.github/workflows/audit.yml` or `.github/workflows/repo-hygiene.yml`.

## 4. SBOM and Release Readiness

### 4.1 SBOM Entry Point

`DEPENDENCY-USAGE.md` is the lightweight SBOM evidence surface for the current repository. It records runtime, dev, prototype, CI/toolchain, license, source boundary, and usage boundary evidence. The release readiness gate (`scripts/release-readiness-gate.py`) and supply-chain governance gate (`scripts/supply-chain-governance-gate.py`) validate that this evidence remains present.

- Dependency inventory (Flutter, Node, Python)
- License inventory (all dependencies must have permissible licenses)
- Generated artifact boundaries (what binary/image/asset is produced and from what source)

### 4.2 License Policy

- Permissible licenses: MIT, Apache-2.0, BSD-2-Clause, BSD-3-Clause, ISC, Unlicense
- Review-required: LGPL-2.1, LGPL-3.0, MPL-2.0
- Prohibited: GPL-2.0, GPL-3.0, AGPL-1.0, AGPL-3.0, SSPL, BUSL-1.1, and any other non-OSI or non-permissive license.

Review-required and prohibited license checks are enforced by `scripts/check_license_policy.py`. License evidence for each dependency is recorded in `DEPENDENCY-USAGE.md`.

## 5. Extension And Module Security

### 5.1 Extension Permissions

Vityo extensions (modules) must declare all required permissions in their manifest. The extension host enforces:
- `same-process` extensions: Dart isolate restrictions, no `dart:io` direct access
- `process` extensions: User OS permissions, validated before launch
- `hosted` extensions: Network permission required, TLS enforced

### 5.2 Extension Vetting

Before activation, extensions are checked for:
- Valid manifest schema
- Known vulnerability database match
- License compatibility
- Permission reasonableness (e.g., a theme extension requesting `network` is suspicious)

### 5.3 Module Manifest Security Baseline

`products/vityo_app/lib/src/view_ide/module_host/module_manifest_security.dart` owns trust checks for module manifests. Manifest security changes must preserve:

1. Schema validation before activation.
2. Deny-by-default behavior for unknown privileged capabilities.
3. Explicit permission rationale for network, process, workspace write, and toolchain execution.
4. A test covering malicious, malformed, or oversized manifest payloads when validation behavior changes.

Governed invariants in `ModuleManifestSecurityPolicy`:
- `allowedPermissions`: `file.read`, `file.write`, `process.exec`, `network`, `secret.read`, `module.install`, `cloud.upload`, `terminal.interactive`
- `allowedChannels`: `stable`, `preview`, `nightly`
- Validation produces `ModuleManifestSecurityCode` for each failure category (missing field, invalid identifier, invalid version, invalid permission, checksum mismatch, signature missing/invalid, platform unsupported, etc.)
- Valid manifests produce `ModuleManifestSecurityStateStatus.trusted`; invalid manifests produce `quarantined` with rollback support.

## 6. Execution Sandbox

### 6.1 Sandbox Contract

`products/vityo_app/lib/src/view_ide/environment/execution/execution_sandbox.dart` owns local execution policy. Security-critical execution must:

1. Build commands from argv arrays, not string concatenation.
2. Avoid shell mode for security-critical paths.
3. Apply workspace, environment, timeout, and permission scopes before process launch.
4. Redact command output before it is logged or exposed to agent context.
5. Return structured denial reasons instead of falling back to unrestricted execution.

Governed invariants in `ExecutionSandboxPolicy`:
- `workspaceRoot`: Root directory for containment checks.
- `trustState`: `trusted` or `restricted` — restricted workspaces block write/network auto-execution.
- `approvalPolicy`: `readOnly`, `workspaceWrite`, `trustedFullAccess`.
- `networkPolicy`: `denied`, `workspaceEndpointsOnly`, `allowed`.
- `allowedEnvironmentKeys`: Key allowlist — environment entries with keys outside the allowlist are rejected.
- `allowedCwdPrefixes`: CWD must be within one of the allowed prefixes (or unrestricted when empty).
- `knownSymlinkPaths`: CWD below a known symlink path is blocked (symlink escape protection).
- `timeout`, `maxStdoutBytes`, `maxStderrBytes`: Bounded resource consumption.

Structured failure modes (`ExecutionSandboxFailureCode`):
`untrustedWorkspace`, `approvalRequired`, `commandRejected`, `cwdOutsideWorkspace`, `pathTraversal`, `symlinkEscape`, `envRejected`, `timeoutInvalid`, `outputLimitInvalid`, `networkBlocked`.

Each failure includes a `message`, `recoveryAction`, `developerDetail`, and `correlationId` for traceability.

### 6.2 Secret Store And Log Redaction

`secret_store.dart` owns credential references and local secret lookup. `log_redactor.dart` owns redaction before logs, diagnostics, runtime output, or agent context are displayed.

`LogRedactor` governed invariants:
1. Pattern-based redaction for: Authorization headers (Bearer/Basic), API key query parameters, JSON key-value secrets, Bearer tokens, `sk-*` OpenAI-style keys, `github_pat_*` tokens, `ghp_*`/`gho_*`/`ghu_*`/`ghs_*`/`ghr_*` tokens, email addresses, POSIX home paths (`/Users/*`, `/home/*`), Windows user paths (`C:\Users\*`), and session IDs.
2. Recursive JSON redaction via `redactJson()` and `redactValue()` — scalar fields matching sensitive key patterns (`authorization`, `apikey`, `token`, `secret`, `password`, `privatekey`, `cloudsessionid`, `hostedsessionid`, etc.) are replaced with `redactedValue` (`<redacted>`).
3. Non-sensitive field-name exceptions: `EnvironmentName`, `focusToken`, `semanticToken`, `tokenKind` are not redacted.

No change may move raw credential values into serialized settings, workspace files, test fixtures, module manifests, or agent journals.

## 7. Build and CI Security

### 7.1 CI Workflow Security

- GitHub Actions workflows use pinned action versions with commit hashes.
- Every workflow action is SHA-pinned, and CI runs `scripts/github-actions-pin-gate.py --mode enforce` to prevent tag-based references from returning.
- Every workflow must declare top-level minimum permissions. The default baseline is `permissions: contents: read`; write scopes require explicit review.
- `pull_request_target` is disabled by policy for repository workflows.
- Secrets are passed via GitHub Secrets, never hardcoded.
- Build artifacts are scanned before deployment.

### 7.2 Executable Governance Gates

CI must keep these checks wired through `.github/workflows/audit.yml` or `.github/workflows/repo-hygiene.yml`:

- `scripts/supply-chain-governance-gate.py` — workflow permissions, Dependabot coverage, SBOM evidence, secret ignore baseline, high-signal secret scan.
- `scripts/dependency-policy-gate.py` — Flutter/Dart and prototype npm dependency registration in `DEPENDENCY-USAGE.md`.
- `scripts/github-actions-pin-gate.py` — action SHA-pinning audit/enforcement.
- `scripts/check_security_baseline.py` — security-critical implementation baseline (required file existence, forbidden pattern scan).
- `scripts/check_license_policy.py` — package allowlist and forbidden license marker checks.

### 7.3 Local Development Security

- `.env` files and local secrets are in `.gitignore`.
- Pre-commit hooks enforce credential scanning (`scripts/repo-hygiene-gate.py`).
- `git secrets` or similar should be configured locally.

### 7.4 Security Baseline Gate

Run:

```bash
python3 scripts/check_security_baseline.py
```

Required security files (must exist):
- `products/vityo_app/lib/src/view_ide/environment/execution/execution_sandbox.dart`
- `products/vityo_app/lib/src/view_ide/environment/configuration/log_redactor.dart`
- `products/vityo_app/lib/src/view_ide/environment/configuration/secret_store.dart`
- `products/vityo_app/lib/src/view_ide/module_host/module_manifest_security.dart`
- `products/vityo_app/lib/src/view_ide/agent_client/agent_permission_model.dart`

Forbidden patterns in security-critical files:
- Silent `catch (_)` — must not silently swallow exceptions.
- `runInShell: true` — security-critical execution must not opt into shell mode.
- String concatenation in `Process.run`/`Process.start` — must use argv arrays.
- Literal `Authorization: Bearer` or `Authorization: Basic` headers — must use credential references.
- `sk-*` API key-like literals — must use credential references.

## 8. Owned Artifacts And Product Boundaries

### 8.1 Governed File Inventory

Every file below participates in the security, permission, audit, or supply-chain boundary. Changes to these files must be reviewed against this policy document and the Code Audit Checklist.

| File | Purpose | Boundary |
|------|---------|----------|
| `packages/vityo_agent_protocol/` | Versioned IDE/Agent messages | Requests, decisions, events, proposals, and receipts |
| `products/vityo_coding_agent/lib/src/policy/` | Agent runtime policy and grant persistence | Tool authority, least privilege, grant lifecycle |
| `products/vityo_coding_agent/lib/src/tools/` | Agent runtime tool catalog and executor | Tool validation, execution, bounds, and results |
| `products/vityo_coding_agent/lib/src/sessions/` | Durable Agent sessions and effect receipts | Journal, replay/recovery, redacted evidence |
| `products/vityo_app/lib/src/view_ide/agent_client/protocol_agent_client.dart` | IDE protocol connection | Message transport and negotiated projection |
| `products/vityo_app/lib/src/view_ide/agent_client/agent_permission_model.dart` | IDE permission presentation plus migration-only role/policy code | Request/decision projection; legacy policy stays governed until removal |
| `products/vityo_app/lib/src/view_ide/agent_client/agent_tool_permission.dart` | Migration-only IDE tool policy | Must remain fail-closed until atomic removal |
| `products/vityo_app/lib/src/view_ide/agent_client/agent_tool_permission_policy_store.dart` | Migration-only IDE policy persistence | Must not become the target permission store |
| `products/vityo_app/lib/src/view_ide/agent_client/agent_tool_sandbox_router.dart` | Migration-only IDE tool execution | Must remain governed until Agent-runtime handoff |
| `products/vityo_app/lib/src/view_ide/agent_client/agent_tool_call_execution_journal.dart` | Migration-only IDE tool journal | Redaction and audit safety until removal |
| `products/vityo_app/lib/src/view_ide/agent_client/agent_session.dart` | IDE Workbench session projection plus legacy state | Permission/change projection; no target durable-session ownership |
| `products/vityo_app/lib/src/view_ide/agent_client/agent_tool_registry.dart` | Migration-only IDE tool registry | Must not accept new runtime tool ownership |
| `products/vityo_app/lib/src/view_ide/environment/execution/execution_sandbox.dart` | Local execution policy: cwd containment, trust, approval, network, env allowlist, timeout | Command safety, resource bounds, structured denial |
| `products/vityo_app/lib/src/view_ide/environment/configuration/log_redactor.dart` | Pattern-based and field-based credential redaction | All log, diagnostic, runtime, and agent-context output redaction |
| `products/vityo_app/lib/src/view_ide/environment/configuration/secret_store.dart` | Credential reference lookup and local secret store | Secret resolution, no raw credential exposure |
| `products/vityo_app/lib/src/view_ide/module_host/module_manifest_security.dart` | Module manifest trust validation, quarantine, rollback | Schema validation, permission allowlist, signature/checksum verification, engine compatibility |
| `scripts/check_security_baseline.py` | Security-critical file existence and forbidden-pattern scan | Required file list, forbidden pattern definitions |
| `scripts/supply-chain-governance-gate.py` | CI/CD and supply-chain governance: workflow permissions, Dependabot, SBOM, secret scan | Workflow security, Dependabot coverage, SBOM markers, secret ignore, secret scan |
| `scripts/dependency-policy-gate.py` | Dependency registration enforcement: every dependency in DEPENDENCY-USAGE.md | pubspec.yaml and package.json dependency registration |
| `scripts/github-actions-pin-gate.py` | GitHub Actions SHA-pinning audit and enforcement | Action version pinning, mode (audit/enforce) |
| `scripts/check_license_policy.py` | Package license allowlist and forbidden-license marker check | License policy, prohibited marker detection |
| `DEPENDENCY-USAGE.md` | Lightweight SBOM: dependency inventory, license, source boundary, usage boundary | SBOM evidence surface |
| `docs/governance/SECURITY-AND-SUPPLY-CHAIN.md` | This policy document | Policy definitions, governed invariants, owned files, downstream consumers |
| `docs/specs/audit/CODE-AUDIT-CHECKLIST.md` | Mandatory audit checklist for agents and reviewers | Seven design principles, lifecycle test coverage, data lifecycle safety, delivery-gate strictness |

### 8.2 Downstream Consumers

The following plan nodes, components, and CI surfaces consume this security contract:

1. **Better Plan security-permissions-audit implementation checkpoint**: Implements the behavior defined by this contract. Changes must satisfy invariants listed in sections 2.4–2.9, 5.3, 6.1–6.2.
2. **Better Plan security-permissions-audit release-evidence checkpoint**: Validates that gates, tests, and documentation satisfy launch readiness.
3. **Better Plan Windows / Linux / macOS desktop adaptation nodes**: Consume execution sandbox and tool permission boundaries for platform-specific process execution.
4. **Better Plan module-extension-contributions and module-runtime-staged-update**: Consume module manifest security policies for extension activation and staged update safety.
5. **Better Plan IDE product hardening**: Consumes protocol permission/change projections and
   workspace transactions; Agent tool execution hardening belongs to the companion runtime track.
6. **Better Plan documentation-governance-release-gates**: Validates that governance gates (supply-chain, security baseline, dependency policy) remain wired in CI.
7. **`.github/workflows/audit.yml` and `.github/workflows/repo-hygiene.yml`**: Wire governance gate scripts into CI execution.
8. **Release readiness gate (`scripts/release-readiness-gate.py`)**: Validates that all governance gates pass before release.

### 8.3 Invariant Summary

| Invariant | Owned By | Enforcement |
|-----------|----------|-------------|
| Dangerous Agent actions have permission/approval/denial/audit | Coding Agent `policy/`, `tools/`, `sessions/`; shared protocol; IDE decision presentation | Runtime policy/journal plus protocol receipt and IDE user decision |
| Credentials redacted in UI, logs, runtime, Agent context | Runtime redaction; IDE `log_redactor.dart`, `secret_store.dart`, context projection | Pattern-based + field-based redaction; security baseline gate scans for raw literals |
| Module manifests validated before activation | `module_manifest_security.dart` | Schema + signature + checksum + permission allowlist + engine compatibility |
| Execution sandbox enforces containment and resource limits | `execution_sandbox.dart` | CWD containment, traversal/symlink detection, env allowlist, timeout, output limits |
| Agent role permissions default to least privilege | Coding Agent `policy/`; legacy IDE `agent_permission_model.dart` until removal | Runtime policy tests; legacy lattice remains fail-closed during migration |
| Dependencies registered in SBOM | `dependency-policy-gate.py` + `DEPENDENCY-USAGE.md` | Gate exits non-zero for unregistered deps |
| CI workflow actions SHA-pinned | `github-actions-pin-gate.py` | Enforce mode |
| High-signal secrets not committed | `supply-chain-governance-gate.py` | Secret scan over `.github/`, `scripts/`, `docs/governance/`, policy files |

### 8.4 Migration To One Ownership Path

The target has one owner per concern: Agent-runtime policy/tools/sessions, shared protocol messages,
and IDE-side consent/change transactions. The IDE currently contains a legacy parallel
provider/tool-loop/policy/session implementation. It is recorded as an implementation gap and must
be removed in one atomic code migration; no new capability may extend that legacy path.

There must be no debug-only, prototype-only, lab-only, or hidden switch that bypasses permission
checks. Capability gaps must appear as structured blocked states with owner, reason, and recovery
path.

## 9. Incident Response

### 9.1 Credential Leak

If a credential is accidentally committed:
1. Immediately revoke the credential from the provider.
2. Purge from git history (`git filter-branch` or `BFG`).
3. Rotate to a new credential.
4. Update credential reference in configuration.

### 9.2 Dependency Vulnerability

If a dependency has a known vulnerability:
1. Assess impact (is Vityo using the vulnerable code path?).
2. Update to patched version if available.
3. If no patch, apply workaround or remove dependency.
4. Document in release notes.

## 10. Cross-Reference

- [API Compatibility](./API-COMPATIBILITY.md)
- [Release Checklist](./RELEASE-CHECKLIST.md)
- [Architecture Runbook](../teams/ARCHITECTURE-RUNBOOK.md)
- [Agent Runtime Runbook](../teams/AGENT-RUNTIME-RUNBOOK.md)
- [Vityo Agent-Native IDE Architecture](../design/Vityo-Agent-Native-IDE-Architecture.md)
- [Code Audit Checklist](../specs/audit/CODE-AUDIT-CHECKLIST.md)
- [Technology Component Inventory](../specs/TECHNOLOGY-COMPONENT-INVENTORY.md)
- [Release Readiness Gate](../../scripts/release-readiness-gate.py)
- [Security Baseline Gate](../../scripts/check_security_baseline.py)
- [Supply Chain Governance Gate](../../scripts/supply-chain-governance-gate.py)
- [Dependency Policy Gate](../../scripts/dependency-policy-gate.py)
- [GitHub Actions Pin Gate](../../scripts/github-actions-pin-gate.py)
