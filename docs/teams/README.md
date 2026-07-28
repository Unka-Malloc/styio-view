# Vityo Team Runbooks

**Purpose:** 定义 `docs/teams/` 的范围、命名和维护规则；产品语义、系统边界、adapter 合同与平台策略仍由现有 SSOT 文档持有。

**Last updated:** 2026-04-16

## Scope

1. 存放 `Vityo` 各维护团队的 daily-work runbook。
2. 提供 ownership、review routing、checkpoint 和 handoff 入口。
3. 跨团队协调统一收在 [COORDINATION-RUNBOOK.md](./COORDINATION-RUNBOOK.md)。
4. 不在这里重写产品规格、系统架构、adapter 合同、上游 handoff 或测试目录细节。

## Naming Rules

1. 团队文件使用 `<TEAM>-RUNBOOK.md`。
2. 总协调入口固定为 `COORDINATION-RUNBOOK.md`。
3. 本目录的人工索引维护在 [INDEX.md](./INDEX.md)。
4. team runbook 只给出入口、边界、门禁和恢复方式，不复制完整 SSOT。

## Maintenance Rules

1. 若一次变更改变了 owned surface、review 触发条件、checkpoint 路径或 handoff 方式，同批更新受影响的 runbook。
2. 若团队边界发生变化，同时更新受影响的 runbook 和 [COORDINATION-RUNBOOK.md](./COORDINATION-RUNBOOK.md)。
3. `scripts/team-docs-gate.py` 是本目录的自动化入口；当 owned surface 变化时，同批更新对应 runbook。
4. 若 runbook 与 owner 文档冲突，以 owner 文档为准。

## Inventory

见 [INDEX.md](./INDEX.md)。
