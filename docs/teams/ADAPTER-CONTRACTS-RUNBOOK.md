# Adapter / Contracts Runbook

**Purpose:** 提供 adapter 合同、integration 层以及上游 `styio` / `spio` handoff 文档的日常维护入口。

**Last updated:** 2026-06-25

## Mission

负责 `Vityo` 自己拥有的 adapter 合同、integration layer 以及对上游的 required handoff。该团队不规划上游内部实现，也不降低前端产品语义去适配临时实现。

## Owned Surface

Primary paths:

1. `frontend/vityo_app/lib/src/backend_toolchain/`
   - `graph_algorithm.dart` — graph DAG, topological sort, Tarjan SCC algorithms
   - `graph_hash.dart` — incremental graph hash computation
   - `toolchain_provenance_guard.dart` — SHA-256 verification, signature policy, endpoint allowlist
   - `workspace_graph_adapter.dart` — workspace graph adapter contract
   - `workspace_graph_builder.dart` — immutable workspace graph builder
   - `workspace_graph_snapshot.dart` — immutable workspace graph snapshot model
2. `frontend/vityo_app/lib/src/integration/`
3. `docs/contracts/`
4. `docs/external/for-styio/`
5. `docs/external/for-spio/`
6. `docs/specs/AGENT-PROVIDER-ADAPTER-SCHEMA.md`
7. `docs/specs/PROFILE-SYNC-ADAPTER-SCHEMA.md`
8. `docs/specs/HOSTED-WORKSPACE-RECORD-SCHEMA.md`

Key SSOTs:

1. `Contracts README -> ../contracts/README.md`
2. `For Styio README -> ../external/for-styio/README.md`
3. `For Spio README -> ../external/for-spio/README.md`
4. `仓库边界 -> ../specs/REPOSITORY-MAP.md`

## Daily Workflow

1. 先判断当前变更属于产品自有合同、对上游的 handoff，还是 integration layer 的消费适配。
2. 合同变化先改 `docs/contracts/` 或对应 schema，再改消费层和测试目录映射。
3. 上游缺能力时，把缺口记在 `external/for-styio/` 或 `external/for-spio/`，不要直接在前端层静默降级产品语义。
4. 若 contract 与既有计划或实现冲突，先显式指出冲突，再改文档和代码。
5. `backend_toolchain/` 是新的后端工具链边界；`integration/` 只保留 legacy export façade，不能在 façade 中继续加入新的解析、路由或 hosted 语义。
6. integration 层的卫生修复如果改变了 workflow selection、runtime event replay、hosted payload 解码、overlay 文件系统枚举覆盖或 Web-only hosted shim，也要同步记录到本 runbook 或对应合同文档，避免代码表面和交接说明漂移。
7. 对 manifest section、target kind、dependency source kind、toolchain source 这类离散 wire value，优先使用共享映射表或 enum helper，不要在多个 parser/adapter 里复制字符串判断。
8. 对 blocked-result、missing-binary、cloud-only fallback 这类 adapter 返回值，优先收成共享 helper，避免 execution / toolchain / runtime adapters 各自维护一份近似但会漂移的消息和状态。
9. hosted execution、hosted workspace、project graph、dependency source、deployment 和 toolchain state 都必须通过 published payload / adapter contract 进入前端，不允许读 `spio` 私有目录或解析 human stderr。
10. `LanguageServiceAdapter` 的 symbol / reference / definition / rename 字段属于编辑器核心合同；本地 token-derived fallback 可以先实现体验，但 adapter handoff 必须保留 declaration range、usage range、declaration-vs-usage 标记、`unresolved-reference` range 和 rename `TextEdit` 计划，不能退化成纯字符串搜索或前端静默改写。
11. Legacy `backend_toolchain/` façade files must stay one-line exports to `view_ide/backend_toolchain/`; adapter contract changes must update the owner path and keep `python3 scripts/check_compat_facades.py` passing.

## Change Classes

1. Small: 合同说明补全、integration 层局部适配或 handoff 文案清理。更新相应索引。
2. Medium: schema 字段、adapter failure 语义、capability snapshot、payload parser、project workflow selection、manifest section parsing、wire-value 映射、runtime event surface 或 legacy façade export 变化。补测试目录映射。
3. High: 主合同分层、责任边界、上游 handoff 模式或 hosted workspace 生命周期变化。走协调 review 并补 ADR。

## Required Gates

Minimum:

```bash
cd frontend/vityo_app && flutter analyze && flutter test
python3 scripts/check_compat_facades.py
python3 scripts/repo-hygiene-gate.py --mode tracked
```

## Cross-Team Dependencies

1. Shell / Editor、Runtime / Agent、Module / Platform 都必须 review 自己消费到的合同变化。
2. Docs / Delivery 必须 review 任何 handoff、里程碑和测试目录映射更新。
3. Theme / UX 在 contract 影响展示层时应共同 review。
4. 若合同变化涉及长期架构边界，必须同步 ADR。

## Handoff / Recovery

Record:

1. 变更的是哪类合同或 handoff 文档。
2. 哪些消费团队已经适配，哪些还未适配。
3. 已补的 schema、计划、测试目录条目。
4. 仍待上游确认的缺口与下一步动作。

2026-06-25: contracts/README.md 更新 — CacheContract 正式列为第九份已发布合同。Vityo-Implementation-Gaps.md 中此前误标为 Closed 的 Remote/browser/virtual providers 与 Cache Contract 已校正为 Partially implemented。
