# Archive Docs

**Purpose:** 保存 `Vityo` 已归档的文档 provenance 和生命周期元数据；活跃摘要留在 `docs/rollups/`，活跃恢复记录留在 `docs/history/`。

**Last updated:** 2026-04-17

## Scope

1. archive manifest 和 ledger。
2. 已归档的历史记录。
3. 未来需要脱离 active tree 的 raw provenance。

## Maintenance Rule

用 `python3 scripts/docs-lifecycle.py refresh` 维护 `ARCHIVE-MANIFEST.json` 与 `ARCHIVE-LEDGER.md` 的同步。不要把仍然活跃的 owner 文档移动到这里来隐藏漂移。
