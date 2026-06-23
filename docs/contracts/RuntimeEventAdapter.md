# RuntimeEventAdapter

**Purpose:** 冻结 runtime surface、debug console 和后续状态机图消费的统一事件壳。

**Last updated:** 2026-04-17

## 1. Envelope Contract

### `RuntimeEventEnvelope`

1. `schemaVersion`
2. `sessionId`
3. `sequence`
4. `timestamp`
5. `eventKind`
6. `origin`
7. `payload`

## 2. First Required Event Families

当前已发布并接入 IDE adapter 的最小 published family：

1. `compile.*`
2. `run.*`
3. `thread.*`
4. `unit.*`
5. `unit.test.*`
6. `state.*`
7. `transition.fired`
8. `log.emitted`
9. `diagnostic.emitted`

当前 `Vityo` 已消费这批 replay 事件并接入：

1. runtime surface 的最小 event replay 摘要
2. runtime surface / debug console 共享的 replay family、payload、route trace 与 debug lane 摘要
3. runtime surface 的 family-based lane summary
4. runtime surface 的最小 execution graph / route checkpoint / node-detail / node-relation / node-timeline / edge-timeline summary
5. runtime surface 的 thread / unit.test / log debug lanes，与 lane trace / filter token / focused timeline detail
6. debug console 的 runtime/host 混合回放、replay window、graph digest、graph node detail / node relation / node timeline / edge timeline、debug digest、lane trace 与 lane filter 摘要
7. shell debug log 的 session-level runtime summary

后续主要扩展方向：

1. richer execution-graph oriented detail payload
2. richer debug-oriented runtime families
3. graph-first runtime UI，不再只依赖卡片和 replay 列表

## 3. Non-Negotiable Rules

1. 事件必须有稳定顺序。
2. 未识别 event kind 只能降级显示，不能把 UI 打崩。
3. runtime graph、thread lanes、debug console 必须都来自同一条 event stream，而不是多条彼此不一致的输出。
4. 当前 published family 先通过 compile-plan artifact 回放，不要求实时流式 transport。
