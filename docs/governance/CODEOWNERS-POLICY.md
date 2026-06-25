# Vityo CODEOWNERS Policy

**Purpose:** 定义 Vityo 仓库的 CODEOWNERS 治理策略、nightly 占位 owner 路由和迁移到真实 GitHub owner 的过渡计划。

**Last updated:** 2026-06-25

**Status:** Nightly advisory owner map - real GitHub team/user owners are not
yet configured for this repository. Root `CODEOWNERS` uses placeholder routing
labels so humans and agents can identify review domains during nightly
integration. Before GitHub code-owner enforcement is enabled, placeholders must
be replaced with real team or user slugs.

## Domain Ownership

Root `CODEOWNERS` currently carries the nightly advisory assignments. When real
GitHub teams or users become available, the same domain assignments should be
converted to enforceable owners:

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
| `.github/pull_request_template.md` | governance-owner | PR evidence checklist |
| `CONTRIBUTING.md` | governance-owner | Contributor workflow |
| `SECURITY.md` | governance-owner | Public security entry |

## Policy

1. **No placeholder owners in enforced production rules.** Do not enable GitHub
   code-owner enforcement with `@architecture-owner`, `@agent-owner`, or any
   other placeholder that GitHub cannot resolve.
2. **Team over individual.** Prefer GitHub teams over individual usernames.
3. **Minimal scope.** Assign ownership to the narrowest path that covers the
   domain.
4. **Review required.** All owned paths require at least one code owner review
   before merge.
5. **Nightly advisory map stays current.** Until real owners exist, root
   `CODEOWNERS` must still route new `view_ide`, sandbox, module security,
   compatibility facade, governance, release, and PR-template paths to the
   closest placeholder domain.

## Transition Plan

When real owners are identified:
1. Replace placeholder entries in root `CODEOWNERS`, or move them to
   `.github/CODEOWNERS` if that is the chosen enforcement location.
2. Use real GitHub team slugs (e.g., `@Unka-Malloc/vityo-agent`).
3. Remove placeholder references from governance documents that describe
   enforceable GitHub settings.
4. Confirm branch rulesets require the relevant code-owner review.
