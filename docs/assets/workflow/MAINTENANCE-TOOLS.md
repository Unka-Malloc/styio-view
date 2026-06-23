# Maintenance Tools

**Purpose:** Define the current Vityo maintenance tool and skill inventory that release gates must verify before publishing.

**Last updated:** 2026-06-19

## Source

The machine-readable source of truth is:

```bash
toolchain/maintenance-tools.json
```

`python3 scripts/release-readiness-gate.py --skip-build` validates this file during release readiness checks.

## Policy

1. Every listed tool and skill must be `current`.
2. The inventory uses `current-only` policy and forbids stale support modes.
3. Every listed tool must point at a repository file that exists.
4. Every skill must be backed by at least one listed tool.
5. Every maintained module or business line must list at least one maintenance tool.
6. Release readiness fails when the inventory is missing, stale, internally inconsistent, or not updated to the release tooling policy date.

## Maintained Lines

The release gate requires coverage for:

1. Adapter / Contracts
2. Coordination
3. Docs / Delivery
4. Foundation / Environment
5. Module / Platform
6. Runtime / Agent
7. Shell / Editor
8. Theme / UX

## Update Flow

1. Add, remove, or replace tools in `toolchain/maintenance-tools.json`.
2. Keep only tools that are useful for development, release, or operations maintenance.
3. Update the affected team runbook when a tool changes a team's daily workflow.
4. Run:

```bash
python3 scripts/release-readiness-gate.py --skip-build
```
