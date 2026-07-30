# Agent Runtime Runbook

**Purpose:** Define the Coding Agent runtime owner's responsibilities, owned paths, review checklist, and required gates. Enforce credential safety, permission audit, patch workflow, and journal/audit compliance.

**Last updated:** 2026-07-30

## Mission

Own the standalone Vityo Coding Agent runtime: model/provider routing, context selection, tools,
policy, coding loops, durable sessions, and multi-agent scheduling. The IDE owns only the protocol
client and collaboration workbench. The Agent never stores raw API keys, directly mutates IDE files,
or bypasses host transactions.

## Owned Surface

Primary paths:
1. `products/vityo_coding_agent/lib/src/`
2. `products/vityo_coding_agent/bin/`
3. `packages/vityo_agent_protocol/`
4. `docs/design/Vityo-Agent-Native-IDE-Architecture.md`
5. `docs/teams/AGENT-RUNTIME-RUNBOOK.md`

IDE Agent Client and Workbench paths are review dependencies, not Agent-runtime-owned surfaces:

1. `products/vityo_app/lib/src/view_ide/agent_client/`
2. `products/vityo_app/lib/src/view_render/agent_workbench/`

Key SSOTs:
1. `Agent architecture -> ../design/Vityo-Agent-Native-IDE-Architecture.md`
2. `安全与供应链 -> ../governance/SECURITY-AND-SUPPLY-CHAIN.md`
3. `API 兼容性 -> ../governance/API-COMPATIBILITY.md`

## Daily Workflow

1. Review PRs touching agent-owned paths against the review checklist.
2. Verify no raw API keys in any serialized output or settings file.
3. Verify display projections redact secrets.
4. Verify new agent tools declare appropriate permission levels.
5. Verify patch workflow goes through workspace edit transaction (not direct file writes).
6. Verify tool calls create journal entries with permission level, timestamp, and outcome.
7. Verify permission model changes fail closed for unknown values and remain compatible with module-contributed tools.
8. Verify security-sensitive changes pass the sandbox/security baseline gate.

## Change Classes

1. Small: New Agent-runtime tool or minor context-selection update. Run focused Coding Agent tests.
2. Medium: New provider kind, runtime policy change, or provider-routing change. Run the focused Coding Agent suite and protocol tests.
3. High: Credential model, context-export contract, or Agent architecture change. Requires security review and an ADR or owning-SSOT update.

## Required Gates

Minimum (select the focused subset appropriate to the change):
```bash
cd products/vityo_coding_agent && dart analyze && dart test
cd packages/vityo_agent_protocol && dart analyze && dart test
python3 scripts/check_security_baseline.py
```

## Cross-Team Dependencies

1. Architecture team must review agent architecture changes.
2. Security/governance team must review credential safety and permission model changes.
3. Editor/shell team must review Agent Client, permission presentation, change application, or Workbench rendering changes.
4. Architecture team must reject any new model/provider, tool-loop, durable-session, or multi-Agent ownership in the IDE.

## Handoff / Recovery

Record:
1. Which agent models were changed.
2. Which permission levels were added or modified.
3. Which credential safety rules were enforced.
4. Which provider configurations were updated.
5. Next recovery point and pending agent features.
