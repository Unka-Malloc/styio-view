# Docs / Delivery Runbook

**Purpose:** 提供 `Vityo` 文档树、里程碑、history、repo hygiene 与交付文档的日常维护入口。

**Last updated:** 2026-06-28

## Mission

负责 docs 树结构、README/INDEX 接线、里程碑与 history 记录、review 队列和 repo hygiene 文档纪律。该团队不替 feature owner 决定产品语义或合同内容，但负责确保这些内容被放在正确的 owner 文档里。

## Owned Surface

Primary paths:

1. `README.md`
2. `docs/`
3. `docs/external/`
4. `scripts/repo-hygiene-gate.py` — updated 2026-06-25: added `cache` language submodule, registered `cache/cache.dart` in canonical language barrel
5. `scripts/docs-index.py`
6. `scripts/docs-lifecycle.py`
7. `scripts/docs-audit.py`
8. `scripts/team-docs-gate.py`
9. `scripts/docs-gate.sh`
10. `scripts/delivery-gate.sh`
11. `scripts/manifest_tool.py`
12. `.github/workflows/project-coverage-gate.yml`
13. `scripts/project-coverage-gate.py`
14. `scripts/python-coverage-gate.py`
15. `scripts/bootstrap-dev-env.sh`
16. `scripts/bootstrap-dev-container.sh`
17. `scripts/bootstrap-dev-env-macos.sh`
18. `scripts/bootstrap-dev-env-windows.ps1`
19. `scripts/bootstrap-workspace.sh`
20. `scripts/bootstrap-workspace.ps1`
21. `scripts/android-sdk-profile.sh`
22. `scripts/android-sdk-profile.ps1`
23. `scripts/apple-platform-profile.sh`
24. `scripts/verify-android-device.sh`
25. `scripts/verify-android-device.ps1`
26. `scripts/verify-apple-device.sh`
27. `docker/`
28. `.devcontainer/`
29. `toolchain/android-sdk-profiles.csv`
30. `toolchain/apple-platform-profiles.csv`
31. `prototype/README.md`
32. `frontend/vityo_app/README.md`
33. `scripts/check_architecture_boundaries.py`
34. `scripts/public-contract-schema-gate.py`
35. `docs/governance/CODEOWNERS-POLICY.md`
36. `docs/rollups/nightly-subbranch-merge-report-20260624.md`
37. `CONTRIBUTING.md`
38. `SECURITY.md`
39. `.github/pull_request_template.md`
40. `docs/governance/`

Key SSOTs:

1. `文档策略 -> ../specs/DOCUMENTATION-POLICY.md`
2. `人机协作规范 -> ../specs/CONTRIBUTOR-AND-AGENT-SPEC.md`
3. `测试目录 -> ../assets/workflow/TEST-CATALOG.md`
4. `文档策略 -> ../specs/DOCUMENTATION-POLICY.md`
5. `当前状态摘要 -> ../rollups/CURRENT-STATE.md`
6. `外部审计入口 -> ../audit/README.md`
7. `活跃缺口登记 -> ../design/Vityo-Implementation-Gaps.md`
8. `IDE 标杆能力矩阵 -> ../design/Vityo-IDE-Benchmark-Matrix.md`
9. `IDE 能力成熟度模型 -> ../design/Vityo-IDE-Capability-Maturity.md`
10. `IDE 交互质量基线 -> ../design/Vityo-IDE-Interaction-Quality-Bar.md`
11. `IDE 能力基线 JSON -> ../../toolchain/vityo-ide-capability-baseline.json`
12. `IDE 产品对标门禁 -> ../../scripts/ide-product-parity-gate.py`
13. `架构边界门禁 -> ../../scripts/check_architecture_boundaries.py`
14. `公共合同 schema 门禁 -> ../../scripts/public-contract-schema-gate.py`
15. `CODEOWNERS 治理策略 -> ../../docs/governance/CODEOWNERS-POLICY.md`
16. `已实现决策摘要 -> ../adr/IMPLEMENTED-DECISIONS.md`

## Daily Workflow

1. 先判断当前变化属于 owner 文档变化，还是目录/索引/交付接线变化。
2. 任何结构性文档变更，都要同步更新对应目录的 `README.md` 和 `INDEX.md`。
3. 若一次变更改变了团队边界、review 路由或 handoff 路径，同批更新 `docs/teams/`。
4. 中断时把恢复信息写入 `docs/history/<topic>.md`，并在正文记录日期；不要只留在聊天或注释里。
5. docs tree 变化时，同批运行 `docs-lifecycle.py`、`docs-index.py`、`docs-audit.py`，而不是只靠 `README/INDEX` 手工刷新；生成式 `INDEX.md` 必须保持跨本地和 GitHub Actions 可复现，空 collection 继承本目录 `README.md` 的 `Last updated`，不得回退到执行当天日期。
6. 根 `.gitignore` 若新增 temp/build/log/cache 类忽略规则，同批补 `docs/**` 与 `frontend/vityo_app/test/**` 的显式 negate 规则，并让 `scripts/repo-hygiene-gate.py` 通过。
7. 仓库级 build/dev-env 文档必须保持固定版本基线显式一致：Debian 13、Python 3.13.5、Node.js v24.15.0 LTS、Flutter 3.41.7 / Dart 3.11.5、Chromium 147.0.7727.116；不得把这类版本描述回退成浮动 `stable`。
8. 容器和宿主机开发环境入口必须一起维护：`Dockerfile`、`.devcontainer/`、Linux/macOS/Windows 一键安装脚本，以及可选 `+android` / `+ios` 组合矩阵，都要在仓库级 build/dev-env 入口里保持同一套说明。
9. Linux Android 工具链是 profile 驱动：`toolchain/android-sdk-profiles.csv`、`scripts/android-sdk-profile.sh`、Linux bootstrap、容器镜像和仓库级 build/dev-env 文档必须同步更新；不得只改单一脚本里的 `android-36` 字面量。
10. Windows Android profile 入口和 macOS Apple profile 入口必须与 Linux 规则同步：`scripts/android-sdk-profile.ps1`、`scripts/apple-platform-profile.sh`、`toolchain/apple-platform-profiles.csv`、macOS/Windows bootstrap 与仓库级 build/dev-env 文档要一起维护，不能只更新单一平台脚本。
11. 真实设备验证入口也属于交付表面：Android bash/PowerShell 验证脚本和 Apple 设备验证脚本必须与 profile CSV、bootstrap、仓库级 build/dev-env 文档同步更新，不能单独漂移。
12. 根 `README.md` 只保留仓库级一跳入口；多平台 bootstrap、profile 切换和真实设备验证的细节统一收在 `docs/BUILD-AND-DEV-ENV.md`，不要在 README、runbook 和子系统文档里各自维护平行说明。
13. 新增 external audit、agent findings、contract package 或 toolchain handoff 时，同批刷新 collection `README.md` / `INDEX.md`，并确保缺口被路由到 owner runbook，而不是停留在审计摘要里。
14. 本轮最小闭环只要求 `repo-hygiene --mode tracked`、`docs-audit`、Flutter analyze/test 和三仓合同测试；product gate 项保持 `VITYO_PRODUCT_GATE=1` 的显式扩展验证，不写成默认必过项。
15. Keep [../specs/POST-COMMIT-CI-CHECKS.md](../specs/POST-COMMIT-CI-CHECKS.md) aligned with actual GitHub Actions monitoring practice whenever commit, push, or CI handoff rules change.
16. 外部上游 handoff 统一收在 `docs/external/for-*`，不要在 docs 根目录重新创建 `for-*` collection。
17. Keep [../specs/TECHNOLOGY-COMPONENT-INVENTORY.md](../specs/TECHNOLOGY-COMPONENT-INVENTORY.md) aligned with `styio-audit` whenever the technology stack, internal components, open-source components, dependency manifests, Apache-2.0 evidence, commercial-risk boundaries, or UI asset-source evidence changes.
18. Maintain GitHub merge gates through Rulesets rather than legacy classic branch protection; audit effective branch rules when required status-check governance changes.
19. External audit shard updates must name the remediated finding, the changed security boundary, and the exact validation command; if code and audit evidence move together, update the owning team runbook in the same change.
20. The ecosystem CLI doc gate (`scripts/ecosystem-cli-doc-gate.py`) is marked non-blocking for cross-repo contract issues; sibling-repo doc failures do not block vityo-nightly PRs. Normal CI must run it for evidence, while `--skip-ecosystem` on `delivery-gate.sh` and `docs-gate.sh` is reserved for targeted recovery.
20. Checkpoint health documentation must list every command run by `scripts/checkpoint-health.sh`; when project coverage, language fixture gate roots, shell-wrapper line-ending policy, prototype governance, or selftest routing changes, update `docs/assets/workflow/CHECKPOINT-HEALTH.md` and the affected owner runbook in the same change.
21. Language-service ADR or contract updates must refresh both the owning contract runbook and generated docs indexes in the same worktree pass; do not rely on passing Flutter tests as evidence that docs ownership is closed.
22. Docs tree structure, milestone files, prototype manifest entries, and fixture paths must be organized by content or functional effect. Version strings, dates, and stage numbers may appear as state metadata or external wire values, but must not define repository directories, entry files, task identities, or implementation routing.
23. Governance docs are part of docs delivery. API compatibility, security, release checklist, CODEOWNERS policy, root contribution/security entries, and PR template changes must keep generated docs indexes current.
24. When a new docs collection is added, update `scripts/docs-index.py` collection metadata and run `python3 scripts/docs-index.py --write` in the same change.
25. Platform-native CI changes must keep `README.md`, `docs/BUILD-AND-DEV-ENV.md`, `.github/workflows/local-ci-gate.yml`, and bootstrap script comments aligned. The PowerShell workspace bootstrap may create Flutter plugin junctions on Windows to avoid Developer Mode or admin symlink requirements, but it must restore tracked `.metadata` and `pubspec.lock` after runner generation and dependency restore.
26. Better Plan workflow state lives only under `docs/plan/better-plan/` and must be validated with `python3 scripts/manifest_tool.py validate docs/plan/better-plan`; owner facts still belong in design, milestone, rollup, review, audit, specs, or external handoff documents.
27. Implemented architectural decisions belong in `docs/adr/IMPLEMENTED-DECISIONS.md` only when they match current code, tests, gates, or owner SSOTs; stale plan residue must be deleted or routed back to active gap/review docs.
28. Repository documentation is English by default. Chinese prose is allowed only when a document's `Purpose` explicitly scopes it as Chinese localization, Chinese translation, or Chinese user-facing product/marketing copy; when touching legacy Chinese prose in non-localized owner docs, convert the touched passage to English.
29. Workspace bootstrap scripts must not leave Flutter template files that are not tracked product tests. When runner generation, Windows LLVM discovery, or platform bootstrap behavior changes, keep bash, PowerShell, and GitHub Actions entry points aligned in the same change.

## Change Classes

1. Small: 链接修复、索引补全、history 补记或局部文案整理。运行 repo hygiene 和 docs gate。
2. Medium: docs 树结构、`docs/external/` handoff 路径、里程碑映射、测试目录映射、audit/agent findings、archive/rollup lifecycle、contract package、post-push CI checking rules、technology/component inventory、version/date/stage-number organization cleanup 或 handoff 路径变化。同步相关入口文档和 docs 自动化脚本。
3. High: owner 文档迁移、文档策略重构、团队边界调整或交付纪律变化。走协调 review。

## Required Gates

Minimum:

```bash
./scripts/docs-gate.sh
python3 scripts/docs-index.py --write
python3 -m pytest tests/test_docs_tooling_coverage.py
python3 scripts/repo-hygiene-gate.py --mode tracked
./scripts/delivery-gate.sh --mode checkpoint --skip-health
```

`scripts/delivery-gate.sh` 会在交付时统一组合 repo hygiene、docs gate、external styio-audit 和 checkpoint health。

## Cross-Team Dependencies

1. 每个 feature 团队都必须 review 会改变其工作流的文档结构变化。
2. Adapter / Contracts 必须 review handoff 和 contract owner 文档的接线变化。
3. Theme / UX 必须 review 会影响 handbook 或视觉基线记录的文档更新。
4. Shell / Editor、Runtime / Agent、Module / Platform 必须各自确认里程碑和测试目录映射没有失真。

## Handoff / Recovery

Record:

1. 更新了哪些 owner 文档、README、INDEX 或 history。
2. 还有哪些目录需要补索引或交付接线。
3. 这批交付影响了哪些 team runbook。
4. 下一个恢复点和需要继续确认的 owner 团队。

2026-06-25: Vityo-Implementation-Gaps.md 校正 — HostedWorkspaceFileSystemProvider 已从 Closed 降为 Partially implemented；Cache Contract 从 Closed 降为 Partially implemented（CacheStore<K,V> 接口未发布、Level 2 持久化未实现）。Vityo-System-Architecture.md、Vityo-Product-Spec.md、CURRENT-STATE.md 日期更新至 2026-06-25。contracts/README.md 新增 CacheContract 为第九条已发布合同。CURRENT-STATE.md 补充 VITYO_PRODUCT_GATE=1 前置条件与已知文档偏差说明。

2026-06-25: Architecture mainstream alignment package merged — added ADR-0010, four architecture/design SSOTs, API compatibility and security/supply-chain governance docs, architecture alignment rollup, and Agent Runtime / Architecture / Extension Module team runbooks. Regenerated docs indexes and refreshed DOC-STATS.md so the new owner documents are represented in docs delivery tracking.

2026-06-28: Windows native compatibility gate repair updated PowerShell bootstrap behavior, Windows validation docs, coverage-gate thresholds, and hosted `windows-latest` evidence expectations. Refresh DOC-STATS.md whenever this runbook changes.

2026-06-28: Better Plan workspace added under `docs/plan/better-plan/` to index existing planning, milestone, gap, rollup, audit, and governance sources without reviving `docs/plan/` as an implementation-plan SSOT. Added `scripts/manifest_tool.py`; validate with `python3 scripts/manifest_tool.py validate docs/plan/better-plan`, then run docs index/audit gates.

2026-06-28: Added `docs/adr/IMPLEMENTED-DECISIONS.md` as the current-code compressed index for implemented architecture decisions. ADR policy now keeps standalone ADRs for decisions still needing direct review, while implemented decisions must carry current implementation or verification anchors.

2026-06-28: Added the English-by-default documentation rule to the documentation policy, contributor/agent spec, and docs delivery workflow. Chinese prose now requires an explicit localization, translation, or Chinese user-facing product/marketing scope.

2026-06-28: Three-platform CI gates now run the delivery health floor on `ubuntu-latest`, `windows-latest`, and `macos-latest`, then prove native Linux, Windows, and macOS Flutter debug builds. Rulesets should require `audit`, `styio-audit`, `local-ci-gate`, `windows-native`, and `macos-native`.

2026-06-28: Added `docs/design/Vityo-End-To-End-Mainstream-IDE-Plan.md` plus separate Linux, Windows, and macOS desktop adaptation plans. Better Plan now keeps `end-to-end-mainstream-ide-alignment` for shared module/workflow convergence and `linux-desktop-adaptation`, `windows-desktop-adaptation`, and `macos-desktop-adaptation` for host-specific evidence.

2026-06-28: Split the end-to-end mainstream IDE work into granular Better Plan entries for app composition, foundation registries, shell, editor buffers, language protocols, project graph/toolchain protocols, execution/debug protocols, agent interaction, user-facing workflows, module contributions, settings/profile/theme, hosted cloud routes, search/navigation/refactor workflows, problems/testing/source-control surfaces, security/audit, and the prototype editor harness.

<!-- codex merge: docs/build/scripts assets imported -->
