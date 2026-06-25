# Vityo Security and Supply Chain Policy

**Purpose:** Define Vityo's security posture and supply chain integrity rules — credential safety, agent permission boundaries, dependency provenance, SBOM, generated artifact policy, and release readiness.

**Owner:** Governance owner (`CODEOWNERS` → governance domain)
**Last updated:** 2026-06-25

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
                                // or secret store ref: "secret://styio/prod/key"
  // NEVER: final String apiKey; ← FORBIDDEN
}
```

### 1.3 Display Redaction

All UI surfaces that display settings or context MUST redact:
- Environment variable values → `[REDACTED]`
- API key references → `[SECRET]`
- Home directory paths → `$HOME/...`
- User-specific paths → `[USER_PATH]/...`

Reference implementations include `log_redactor.dart`, `secret_store.dart`, and the agent context projection code. Any new display surface must use the redacted projection, not raw provider configuration.

## 2. Agent Permission Boundaries

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

- Remote provider connections must use TLS.
- Agent tool calls requiring network must declare `network` scope.
- Network requests from agent tools are subject to timeout and rate limiting.

### 2.4 Permission Model File

`frontend/vityo_app/lib/src/view_ide/agent/agent_permission_model.dart` is the governed permission model. Changes to permission names, ordering, default behavior, or approval text must be reviewed as compatibility and security changes.

Required evidence:

1. Existing tool declarations still parse.
2. Unknown or malformed permission values fail closed.
3. Permission elevation is journaled.
4. Displayed context is redacted before it reaches the agent surface.

## 3. Dependency Provenance

### 3.0 Automated Update Coverage

Dependabot is configured in `.github/dependabot.yml` for:

- GitHub Actions workflows at `/`
- Flutter/Dart `pub` dependencies at `/frontend/vityo_app`
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

## 4. SBOM and Release Readiness

### 4.1 SBOM Entry Point

`DEPENDENCY-USAGE.md` is the lightweight SBOM evidence surface for the current repository. It records runtime, dev, prototype, CI/toolchain, license, source boundary, and usage boundary evidence. The release readiness gate (`scripts/release-readiness-gate.py`) and supply-chain governance gate (`scripts/supply-chain-governance-gate.py`) validate that this evidence remains present.

- Dependency inventory (Flutter, Node, Python)
- License inventory (all dependencies must have permissible licenses)
- Generated artifact boundaries (what binary/image/asset is produced and from what source)

### 4.2 License Policy

- Permissible licenses: MIT, Apache-2.0, BSD-2-Clause, BSD-3-Clause, ISC, Unlicense
- Review-required: LGPL-2.1, LGPL-3.0, MPL-2.0
- Prohibited: GPL-2.0, GPL-3.0, AGPL-3.0 (unless Vityo itself adopts GPL)

### 4.3 Generated Artifact Policy

Generated artifacts (build outputs, bundled assets, code-generated files) must:
1. Have a clear source-of-truth in the repository
2. Be reproducible from source via documented build steps
3. Not contain credentials, secrets, or environment-specific data
4. Be excluded from code review diff by `.gitignore` where appropriate

### 4.4 Binary / Image / Asset Hygiene

New binary files, images, or generated assets must be approved via the repo hygiene allowlist (`scripts/repo-hygiene-gate.py`). Do not relax general rules for individual assets.

## 5. Extension Security

### 5.1 Extension Permissions

Extensions must declare all required permissions in their manifest. The extension host enforces:
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

`frontend/vityo_app/lib/src/view_ide/module_host/module_manifest_security.dart` owns trust checks for module manifests. Manifest security changes must preserve:

1. Schema validation before activation.
2. Deny-by-default behavior for unknown privileged capabilities.
3. Explicit permission rationale for network, process, workspace write, and toolchain execution.
4. A test covering malicious, malformed, or oversized manifest payloads when validation behavior changes.

## 6. Execution Sandbox

### 6.1 Sandbox Contract

`frontend/vityo_app/lib/src/view_ide/environment/execution/execution_sandbox.dart` owns local execution policy. Security-critical execution must:

1. Build commands from argv arrays, not string concatenation.
2. Avoid shell mode for security-critical paths.
3. Apply workspace, environment, timeout, and permission scopes before process launch.
4. Redact command output before it is logged or exposed to agent context.
5. Return structured denial reasons instead of falling back to unrestricted execution.

### 6.2 Secret Store And Log Redaction

`secret_store.dart` owns credential references and local secret lookup. `log_redactor.dart` owns redaction before logs, diagnostics, runtime output, or agent context are displayed.

No change may move raw credential values into serialized settings, workspace files, test fixtures, module manifests, or agent journals.

## 7. Build and CI Security

### 7.1 CI Workflow Security

- GitHub Actions workflows use pinned action versions with commit hashes.
- Until every workflow action is SHA-pinned, `scripts/github-actions-pin-gate.py --mode audit` must run in CI and release readiness can promote it to `--mode enforce`.
- Every workflow must declare top-level minimum permissions. The default baseline is `permissions: contents: read`; write scopes require explicit review.
- `pull_request_target` is disabled by policy for repository workflows.
- Secrets are passed via GitHub Secrets, never hardcoded.
- Build artifacts are scanned before deployment.

### 7.2 Executable Governance Gates

CI must keep these checks wired through `.github/workflows/audit.yml` or `.github/workflows/repo-hygiene.yml`:

- `scripts/supply-chain-governance-gate.py` - workflow permissions, Dependabot coverage, SBOM evidence, secret ignore baseline, high-signal secret scan.
- `scripts/dependency-policy-gate.py` - Flutter/Dart and prototype npm dependency registration in `DEPENDENCY-USAGE.md`.
- `scripts/github-actions-pin-gate.py` - action SHA-pinning audit/enforcement.
- `scripts/check_security_baseline.py` - security-critical implementation baseline.
- `scripts/check_license_policy.py` - package allowlist and forbidden license marker checks.

### 7.3 Local Development Security

- `.env` files and local secrets are in `.gitignore`.
- Pre-commit hooks enforce credential scanning (`scripts/repo-hygiene-gate.py`).
- `git secrets` or similar should be configured locally.

### 7.4 Security Baseline Gate

Run:

```bash
python3 scripts/check_security_baseline.py
```

The gate requires the sandbox, log redactor, secret store, module manifest security, and agent permission model files to exist, and rejects known-dangerous patterns such as silent security catches, shell-mode execution in critical paths, string-built subprocess commands, literal authorization headers, and API-key-like literals.

## 8. Incident Response

### 8.1 Credential Leak

If a credential is accidentally committed:
1. Immediately revoke the credential from the provider.
2. Purge from git history (`git filter-branch` or `BFG`).
3. Rotate to a new credential.
4. Update credential reference in configuration.

### 8.2 Dependency Vulnerability

If a dependency has a known vulnerability:
1. Assess impact (is Vityo using the vulnerable code path?).
2. Update to patched version if available.
3. If no patch, apply workaround or remove dependency.
4. Document in release notes.

## 9. Cross-Reference

- [API Compatibility](./API-COMPATIBILITY.md)
- [Release Checklist](./RELEASE-CHECKLIST.md)
- [Architecture Runbook](../teams/ARCHITECTURE-RUNBOOK.md)
- [Agent Runtime Runbook](../teams/AGENT-RUNTIME-RUNBOOK.md)
- [Vityo Agent Runtime Architecture](../design/Vityo-Agent-Runtime-Architecture.md)
- [Release Readiness Gate](../../scripts/release-readiness-gate.py)
