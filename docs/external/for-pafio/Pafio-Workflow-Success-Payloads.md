# Pafio Workflow Success Payloads

**Purpose:** 冻结 `styio-view` 对 `pafio` workflow success payload 的 handoff 要求。

**Last updated:** 2026-04-17

## 1. Versioned Project Execution Success Payloads

当前项目执行主线使用这些 canonical CLI forms：

```text
pafio --json build --manifest-path <path> ...
pafio --json run --manifest-path <path> ...
pafio --json test --manifest-path <path> ...
```

当前 published payload family：

1. `workflow_success_payloads v1`

`workflow_success_payloads v1` 至少需要：

1. command metadata
2. `build_root`
3. `artifact_dir`
4. `diag_dir`
5. `receipt_path`
6. parsed `receipt`
7. `diagnostics_path`
8. `runtime_events_path`
9. `runtime_session_id`
10. parsed `runtime_events`
11. captured `stdout`
12. captured `stderr`

当前 `runtime_events` 基线至少承载：

1. `compile.*`
2. `run.*`
3. `thread.*`
4. `unit.*`
5. `unit.test.*`
6. `state.*`
7. `transition.fired`
8. `log.emitted`
9. `diagnostic.emitted`

## 2. Stable JSON Success For Supporting Commands

除 `workflow_success_payloads v1` 外，`styio-view` 当前还依赖这些 canonical CLI forms 的成功 JSON：

```text
pafio --json fetch --manifest-path <path> ...
pafio --json vendor --manifest-path <path> ...
pafio --json pack --manifest-path <path> ...
pafio --json publish --manifest-path <path> --dry-run
pafio --json publish --manifest-path <path> --registry <path-or-url>
pafio --json tool install --styio-bin <path>
pafio --json tool use --version <compiler-version> [--channel <channel>]
pafio --json tool pin (--version <compiler-version> [--channel <channel>] | --clear) [--manifest-path <path>]
```

这些 supporting commands 当前可以不是共享 versioned family，但成功时仍必须：

1. 向 stdout 写一个稳定 JSON object
2. 至少包含 `command`
3. 至少包含 `message`
4. 按命令补充路径或状态字段，例如 `archive_path`、`package`、managed compiler path 或 pin path

## 3. Rules

1. 不能只有 failure JSON；成功也必须有稳定机器输出。
2. `build/run/test` 使用 `workflow_success_payloads v1`，并作为 IDE 项目执行主线。
3. supporting commands 的成功 JSON 也必须稳定，因为 `styio-view` 已通过这些命令驱动 fetch/vendor、pack/publish 和 toolchain lifecycle。
4. `styio-view` 不解析 prose stderr 来判断 workflow 是否成功。
