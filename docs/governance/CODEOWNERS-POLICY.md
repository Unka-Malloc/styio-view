# Vityo CODEOWNERS Policy

**Purpose:** 定义 Vityo 仓库的 CODEOWNERS 治理策略和过渡计划。当前未配置真实 GitHub owner，本文档作为治理策略，直到真实 owner 分配为止。

**Last updated:** 2026-06-24

**Status:** Draft — no real GitHub team/user owners are configured for this
repository. This document serves as the governance policy until real owners
are assigned.

## Domain Ownership

When real GitHub teams or users become available, `.github/CODEOWNERS` should
be created with the following domain assignments:

| Path Pattern | Owner | Scope |
|---|---|---|
| `frontend/vityo_app/lib/src/view_ide/agent/` | agent-owner | Agent runtime, tools, permissions |
| `frontend/vityo_app/lib/src/view_ide/runtime/` | runtime-owner | Debug/runtime contracts, execution |
| `frontend/vityo_app/lib/src/view_ide/workspace/` | workspace-owner | Workspace model, source control |
| `frontend/vityo_app/lib/src/view_ide/language/` | language-owner | Language service, diagnostics |
| `frontend/vityo_app/lib/src/view_ide/module_host/` | module-owner | Extension/module host |
| `frontend/vityo_app/lib/src/view_ide/commands/` | commands-owner | Command registry, permissions |
| `frontend/vityo_app/lib/src/view_render/` | shell-owner | View render surface |
| `frontend/vityo_app/lib/src/backend_toolchain/` | adapter-owner | Adapter contracts |
| `prototype/` | prototype-owner | Prototype editor |
| `docs/` | docs-owner | Documentation |
| `scripts/` | docs-owner | Tooling, gates |
| `toolchain/` | docs-owner | Toolchain manifests |
| `.github/workflows/` | ci-owner | CI/CD workflows |

## Policy

1. **No placeholder owners in production.** Do not commit a `.github/CODEOWNERS`
   file containing `@architecture-owner`, `@agent-owner`, or any other
   placeholder that GitHub cannot resolve.
2. **Team over individual.** Prefer GitHub teams over individual usernames.
3. **Minimal scope.** Assign ownership to the narrowest path that covers the
   domain.
4. **Review required.** All owned paths require at least one code owner review
   before merge.

## Transition Plan

When real owners are identified:
1. Replace this file with `.github/CODEOWNERS`.
2. Use real GitHub team slugs (e.g., `@Unka-Malloc/vityo-agent`).
3. Remove placeholder references from all other governance documents.
