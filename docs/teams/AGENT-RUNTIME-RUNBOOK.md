# Agent Runtime Runbook

**Purpose:** Define the agent domain owner's responsibilities, owned paths, review checklist, and required gates for Vityo's agent runtime system. Enforce credential safety, permission audit, patch workflow, and journal/audit compliance.

**Last updated:** 2026-06-24

## Mission

Own the Vityo agent runtime: agent context model, provider routing, tool permission system, patch workflow, session management, and journal/audit trail. Enforce that agent never stores raw API keys, never directly writes files, never bypasses the document model, and always journals tool calls with permission levels.

## Owned Surface

Primary paths:
1. `frontend/vityo_app/lib/src/view_ide/agent/`
   - `agent_permission_model.dart` - governed permission model for agent tools and sandbox routing
2. `frontend/vityo_app/lib/src/agent/`
3. `frontend/vityo_app/lib/src/view_render/agent/`
4. `docs/design/Vityo-Agent-Runtime-Architecture.md`
5. `docs/teams/AGENT-RUNTIME-RUNBOOK.md`

Key SSOTs:
1. `Agent 架构 -> ../design/Vityo-Agent-Runtime-Architecture.md`
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

1. Small: New agent tool, minor context model update. Run flutter test on agent tests.
2. Medium: New provider kind, permission model change, provider routing change. Run full agent test suite plus flutter analyze.
3. High: Credential model change, context scope redefinition, agent architecture change. Requires security review and ADR.

## Required Gates

Minimum:
```bash
cd frontend/vityo_app && flutter test test/agent_context_test.dart test/agent_settings_test.dart test/agent_permission_policy_test.dart test/agent_patch_transaction_test.dart
cd frontend/vityo_app && flutter analyze
python3 scripts/check_security_baseline.py
```

## Cross-Team Dependencies

1. Architecture team must review agent architecture changes.
2. Security/governance team must review credential safety and permission model changes.
3. Editor/shell team must review agent surface rendering changes.
4. Module team must review agent provider/tool extension contributions.

## Handoff / Recovery

Record:
1. Which agent models were changed.
2. Which permission levels were added or modified.
3. Which credential safety rules were enforced.
4. Which provider configurations were updated.
5. Next recovery point and pending agent features.
