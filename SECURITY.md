# Vityo Security Policy

**Purpose:** Provide the public security entry point for Vityo nightly and route maintainers to the detailed governance policy.

**Last updated:** 2026-06-25

## Supported Branch

Security fixes are handled on the active `nightly` integration line unless maintainers explicitly name a release branch. This repository is a downstream nightly repository; upstream contract changes may also require coordinated fixes in `styio` or `pafio`.

## Reporting A Vulnerability

Do not open a public issue containing secrets, exploit steps, or live credentials. Report privately to the maintainers through the repository owner channel, then include:

1. Affected path, feature, or adapter contract.
2. Reproduction steps using placeholders instead of real secrets.
3. Impacted platform: desktop, Web, Android, iOS, hosted workspace, agent, module host, or toolchain.
4. Whether the issue involves credential storage, sandbox escape, command execution, module manifest trust, dependency provenance, or release artifacts.

## Security Rules For Contributors

1. Never commit raw API keys, tokens, passwords, or provider credentials.
2. Store credential references, not credential values.
3. Redact secrets and user-specific paths before logs, diagnostics, screenshots, and agent context are displayed.
4. Route subprocess execution through the sandbox policy and argv-based command construction.
5. Treat module manifests and agent tool declarations as untrusted external input until validated.
6. Add negative tests for unauthorized, malformed, timeout, and oversized input paths when security-sensitive code changes.

## Required Local Gate

Run from the repository root:

```bash
python3 scripts/check_security_baseline.py
```

The baseline tracks these security-critical files:

1. `frontend/vityo_app/lib/src/view_ide/environment/execution/execution_sandbox.dart`
2. `frontend/vityo_app/lib/src/view_ide/environment/configuration/log_redactor.dart`
3. `frontend/vityo_app/lib/src/view_ide/environment/configuration/secret_store.dart`
4. `frontend/vityo_app/lib/src/view_ide/module_host/module_manifest_security.dart`
5. `frontend/vityo_app/lib/src/view_ide/agent/agent_permission_model.dart`

## Detailed Policy

The detailed security, supply-chain, sandbox, agent permission, module manifest security, SBOM, and incident-response policy lives in [docs/governance/SECURITY-AND-SUPPLY-CHAIN.md](docs/governance/SECURITY-AND-SUPPLY-CHAIN.md).
