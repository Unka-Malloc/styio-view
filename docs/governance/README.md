# Vityo Governance

**Purpose:** Define the repository-owned rules for compatibility, security, release readiness, code ownership, and migration discipline.

**Last updated:** 2026-06-25

## Scope

`docs/governance/` owns policy that must be checked before a change is merged or released. Product semantics stay in `docs/design/`, adapter contracts stay in `docs/contracts/`, and team-specific daily workflow stays in `docs/teams/`.

This directory is the right place for:

1. API compatibility and deprecation policy.
2. Security, supply-chain, sandbox, agent permission, and module manifest policy.
3. CODEOWNERS transition policy.
4. Release readiness and checkpoint checklist.

## Entry Points

1. API compatibility: [API-COMPATIBILITY.md](./API-COMPATIBILITY.md)
2. Security and supply chain: [SECURITY-AND-SUPPLY-CHAIN.md](./SECURITY-AND-SUPPLY-CHAIN.md)
3. CODEOWNERS policy: [CODEOWNERS-POLICY.md](./CODEOWNERS-POLICY.md)
4. Release checklist: [RELEASE-CHECKLIST.md](./RELEASE-CHECKLIST.md)

## Maintenance Rules

1. Any new public `view_ide/` contract, module manifest field, agent tool interface, or compatibility facade must update [API-COMPATIBILITY.md](./API-COMPATIBILITY.md).
2. Any sandbox, credential, redaction, agent permission, module manifest security, dependency, or release-signing change must update [SECURITY-AND-SUPPLY-CHAIN.md](./SECURITY-AND-SUPPLY-CHAIN.md).
3. Any release gate or checkpoint floor change must update [RELEASE-CHECKLIST.md](./RELEASE-CHECKLIST.md) and the local dev entry in [../BUILD-AND-DEV-ENV.md](../BUILD-AND-DEV-ENV.md).
4. Any owner-routing change must update [CODEOWNERS-POLICY.md](./CODEOWNERS-POLICY.md), root [../../CODEOWNERS](../../CODEOWNERS), and affected team runbooks together.
5. After adding or removing governance files, run `python3 scripts/docs-index.py --write` from the repository root.
