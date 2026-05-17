# ExecutionAdapter

**Purpose:** 冻结 compile/run 会话与其机器输出；`Vityo` 的保存、运行、debug console 与 runtime surface 都围绕本合同消费结果。

**Last updated:** 2026-04-21

## 1. Session Contract

### 1.1 `ExecutionSession`

1. `sessionId`
2. `kind`
3. `unitRange`
4. `status`
5. `statusMessage`
6. `diagnostics[]`
7. `stdoutEvents[]`
8. `stderrEvents[]`

### 1.2 `ExecutionLogEvent`

1. `timestamp`
2. `origin`
3. `message`

### 1.3 Hosted Execution Envelope

当 adapter 走 hosted/cloud 路由时，`ExecutionSession` 和 `RuntimeEventAdapter` 都绑定在同一个 execution envelope 上。前端依赖：

1. top-level `returncode`
2. top-level `message`
3. top-level `stdout`
4. top-level `stderr`
5. `payload` 或 `error_payload`
6. `payload.session_id`
7. `payload.runtime_events[]`
8. `payload.diagnostics[]`
9. `payload.stdout`
10. `payload.stderr`

## 2. Required Behaviors

1. 能明确区分 `succeeded / failed / blocked / running`。
2. diagnostics 必须结构化返回，不允许只靠 stderr 文本解析。
3. 如果某条执行路径当前未发布，adapter 必须返回 `blocked` 和清晰原因。
4. 单文件 scratch 路径与项目路径可以拥有不同实现，但都必须落在同一 session 合同上。
5. hosted 模式下，runtime events、diagnostics、stdout/stderr 都必须从 execution envelope 读取，不能假设存在单独的事件流或未文档化 side channel。

## 3. Product Assumptions

1. 主线先支持 `CLI Adapter`。
2. `FFI Adapter` 是统一本地原生接入标识，不绑定某个专门的仓库名。
3. `Cloud Adapter` 是移动端与 hosted workspace 的补充执行路径。
