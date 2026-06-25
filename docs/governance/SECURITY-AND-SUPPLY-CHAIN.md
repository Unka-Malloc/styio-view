# Vityo Security and Supply Chain Policy

**Purpose:** Define Vityo's security posture and supply chain integrity rules — credential safety, agent permission boundaries, dependency provenance, SBOM, generated artifact policy, and release readiness.

**Owner:** Governance owner (`CODEOWNERS` → governance domain)
**Last updated:** 2026-06-24

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

Reference: `AgentRedactionPolicy` in `agent_context.dart`

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

## 3. Dependency Provenance

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

The release readiness gate (`scripts/release-readiness-gate.py`) includes SBOM checks:

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

## 6. Build and CI Security

### 6.1 CI Workflow Security

- GitHub Actions workflows use pinned action versions with commit hashes.
- Secrets are passed via GitHub Secrets, never hardcoded.
- Build artifacts are scanned before deployment.

### 6.2 Local Development Security

- `.env` files and local secrets are in `.gitignore`.
- Pre-commit hooks enforce credential scanning (`scripts/repo-hygiene-gate.py`).
- `git secrets` or similar should be configured locally.

## 7. Incident Response

### 7.1 Credential Leak

If a credential is accidentally committed:
1. Immediately revoke the credential from the provider.
2. Purge from git history (`git filter-branch` or `BFG`).
3. Rotate to a new credential.
4. Update credential reference in configuration.

### 7.2 Dependency Vulnerability

If a dependency has a known vulnerability:
1. Assess impact (is Vityo using the vulnerable code path?).
2. Update to patched version if available.
3. If no patch, apply workaround or remove dependency.
4. Document in release notes.

## 8. Cross-Reference

- [API Compatibility](./API-COMPATIBILITY.md)
- [Architecture Runbook](../teams/ARCHITECTURE-RUNBOOK.md)
- [Agent Runtime Runbook](../teams/AGENT-RUNTIME-RUNBOOK.md)
- [Vityo Agent Runtime Architecture](../design/Vityo-Agent-Runtime-Architecture.md)
- [Release Readiness Gate](../../scripts/release-readiness-gate.py)
