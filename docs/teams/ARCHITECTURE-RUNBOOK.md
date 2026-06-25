# Architecture Runbook

**Purpose:** Define the architecture domain owner's responsibilities, owned paths, review checklist, and required gates for Vityo system architecture governance.

**Last updated:** 2026-06-24

## Mission

Own the overall Vityo system architecture: layer boundaries, import rules, adapter contract schemas, architecture alignment with mainstream IDE patterns, and architecture decision records (ADRs). Enforce that view_ide doesn't import Flutter presentation, view_render doesn't import agent providers, and backend_toolchain stays a shim-only legacy facade.

## Owned Surface

Primary paths:
1. `docs/design/Vityo-Mainstream-Architecture-Alignment.md`
2. `docs/design/Vityo-System-Architecture.md`
3. `docs/design/Vityo-Protocol-And-Capability-Negotiation.md`
4. `docs/design/Vityo-Extension-And-Contribution-Model.md`
5. `docs/design/Vityo-Agent-Runtime-Architecture.md`
6. `docs/adr/`
7. `docs/teams/ARCHITECTURE-RUNBOOK.md`
8. `docs/governance/`
9. `CODEOWNERS`
10. `scripts/check_architecture_boundaries.py`
11. `scripts/check_compat_facades.py`

Key SSOTs:
1. `架构对齐 -> ../design/Vityo-Mainstream-Architecture-Alignment.md`
2. `系统架构 -> ../design/Vityo-System-Architecture.md`
3. `协议协商 -> ../design/Vityo-Protocol-And-Capability-Negotiation.md`
4. `API 兼容性 -> ../governance/API-COMPATIBILITY.md`
5. `供应链安全 -> ../governance/SECURITY-AND-SUPPLY-CHAIN.md`

## Daily Workflow

1. Review PRs touching architecture-owned paths against the review checklist.
2. Run `python3 scripts/check_architecture_boundaries.py` on any `view_ide` / `view_render` changes.
3. Ensure new public models have schemaVersion fields.
4. Ensure new adapter payloads have capabilities maps and unknown field tolerance.
5. Verify no competitor brand names enter UI-visible strings.
6. Create ADRs for significant architectural decisions.
7. Keep legacy `backend_toolchain/`, `editor/`, and `language/` roots as one-line compatibility facades only.

## Change Classes

1. Small: New model/contract in existing domain, minor doc update. Run architecture boundary gate and flutter analyze.
2. Medium: New architecture doc, new ADR, new governance rule, layer boundary adjustment. Run full gate suite plus docs gate.
3. High: Layer boundary redefinition, major schema version bump, breaking contract change. Requires ADR, team review, and migration guide.

## Required Gates

Minimum:
```bash
python3 scripts/check_architecture_boundaries.py
python3 scripts/check_compat_facades.py
python3 scripts/ide-product-parity-gate.py
python3 scripts/vityo-ide-product-gate.py --mode checkpoint
cd frontend/vityo_app && flutter analyze
python3 scripts/repo-hygiene-gate.py --mode tracked
```

## Cross-Team Dependencies

1. Agent team must review agent architecture changes.
2. Module team must review extension/contribution model changes.
3. Adapter contracts team must review protocol and capability negotiation changes.
4. Editor/shell team must review view_ide/view_render boundary changes.
5. Governance team must review security and API compatibility changes.

## Handoff / Recovery

Record:
1. Which architecture docs were updated.
2. Which ADRs were created or superseded.
3. Which layer boundaries were adjusted.
4. Which gates were updated.
5. Next recovery point and pending architectural decisions.
