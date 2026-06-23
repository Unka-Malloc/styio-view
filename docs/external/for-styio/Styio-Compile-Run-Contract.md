# Styio Compile Run Contract

**Purpose:** 冻结 `Vityo` 与上游 `styio` 在执行、runtime 事件、compile-plan consumer 和 machine-info 扩展上的对接边界。

**Last updated:** 2026-04-17

## 1. Required Execution Handoff

上游 `styio` 需要提供：

1. `resolveMinimalCompilableUnit`
2. `compile request / result`
3. `run request / result`
4. `stdout / stderr / diagnostics` machine stream

## 2. Required Runtime Event Handoff

第一批至少需要：

1. `compile.*`
2. `run.*`
3. `thread.*`
4. `unit.*`
5. `unit.test.*`
6. `state.*`
7. `transition.fired`
8. `log.emitted`
9. `diagnostic.emitted`

每个事件至少应带：

1. `schemaVersion`
2. `sessionId`
3. `sequence`
4. `timestamp`
5. `eventKind`
6. `origin`
7. `payload`

## 3. Compile-Plan Consumer

当前已发布的 `styio` contract：

1. `styio --compile-plan <path>` 接受 `spio` 输出的 published compile plan
2. 明确 accept / reject path
3. 失败时返回 machine-readable payload
4. `build/check/run/test` 都走同一条 published compile-plan 入口
5. invalid plan / CLI conflict 也返回 machine-readable `CliError`
6. compile-plan 成功路径会在约定的 `build_root / artifact_dir / diag_dir` 内写出 receipt、产物和 `diagnostics.jsonl`
7. `styio --machine-info=json` 现在广告 `supported_contracts.runtime_events:[1]`
8. published compile-plan 现在会写出 `build_root/runtime-events.jsonl`
9. `receipt.json` 现在包含 `session_id` 与 `outputs.runtime_events_path`

当前缺口不再是 compile-plan consumer 本身，而是：

1. compile/run session result 的更完整 machine envelope
2. language-service / runtime surface 所需的更多稳定 payload
3. debug-oriented runtime families 与更细粒度 graph semantics

当前 `Vityo` 的 project route 已不再停留在 preview-only：

1. 项目图优先消费 `spio project-graph --json`
2. 项目执行优先消费 `spio build/run/test --json` 的 `workflow_success_payloads` published family
3. `styio` 继续作为 compile-plan consumer 与 receipt / diagnostics 的真相源

## 4. Machine-Info Extension

`styio --machine-info=json` 现在至少必须包含：

1. `active_integration_phase`
2. `supported_contract_versions`
3. `supported_adapter_modes`
4. `feature_flags`
5. `supported_contracts.compile_plan:[1]`
6. `supported_contracts.runtime_events:[1]`
7. `feature_flags.runtime_event_stream:true`

## 5. Rules

1. `Vityo` 不解析人类 stderr 来猜状态。
2. 未发布的执行路径必须明确返回 `blocked` 原因，而不是让前端猜测。
3. 上游可以只先交付 `CLI` 或 `FFI` 中的一种，但 shape 必须满足 `docs/contracts/ExecutionAdapter.md` 与 `docs/contracts/RuntimeEventAdapter.md`。
4. 项目执行主线优先消费 `spio --json build/run/test`，`styio` 继续作为 compile-plan consumer 与 receipt / diagnostics 的真相源。
