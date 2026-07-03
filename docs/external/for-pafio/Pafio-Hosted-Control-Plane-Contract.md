# Pafio Hosted Control-Plane Contract

**Purpose:** Record the frontend-facing hosted workspace API that `styio-view` consumes from `pafio` so UI and backend teams can ship independently against a fixed contract package.

**Last updated:** 2026-04-21

## Source Of Truth

The backend-owned machine contract lives in `styio-pafio`:

- `contracts/hosted-control-plane/v1/openapi.json`
- `contracts/hosted-control-plane/v1/workflows.arazzo.json`
- `contracts/hosted-control-plane/v1/hosted-control-plane.contract.json`
- `contracts/hosted-control-plane/v1/hosted-control-plane.examples.json`
- `contracts/hosted-control-plane/v1/redocly.yaml`

`styio-view` consumes that versioned package. This document is the consumer-side handoff note, not a second source of truth.

## Fixed Base Path

`styio-view` treats the hosted API family as:

`/api/styio-hosted/v1`

The base URL may change per environment, but the versioned path family and operation spellings are fixed by contract.

## Fixed Route Set

1. `POST /workspaces/open`
2. `GET /workspaces/{workspace_id}/project-graph`
3. `POST /workspaces/{workspace_id}/tool/install`
4. `POST /workspaces/{workspace_id}/tool/use`
5. `POST /workspaces/{workspace_id}/tool/pin`
6. `POST /workspaces/{workspace_id}/tool/clear-pin`
7. `POST /workspaces/{workspace_id}/dependencies/fetch`
8. `POST /workspaces/{workspace_id}/dependencies/vendor`
9. `POST /workspaces/{workspace_id}/execution/run`
10. `POST /workspaces/{workspace_id}/execution/build`
11. `POST /workspaces/{workspace_id}/execution/test`
12. `POST /workspaces/{workspace_id}/deployment/pack`
13. `POST /workspaces/{workspace_id}/deployment/preflight`
14. `POST /workspaces/{workspace_id}/deployment/publish`

## Frontend Surface Mapping

Every frontend/backend interaction now has a fixed contract entrypoint:

| Frontend surface | Adapter method or lane | OpenAPI `operationId` | Route |
|------------------|------------------------|------------------------|-------|
| hosted workspace bootstrap | `ProjectGraphAdapter.loadProjectGraph()` first load | `openWorkspace` | `POST /workspaces/open` |
| hosted project refresh | `ProjectGraphAdapter.loadProjectGraph()` refresh | `projectGraph` | `GET /workspaces/{workspace_id}/project-graph` |
| managed compiler install | `ToolchainManagementAdapter.installManagedCompiler()` | `toolInstall` | `POST /workspaces/{workspace_id}/tool/install` |
| managed compiler activate | `ToolchainManagementAdapter.useManagedCompiler()` | `toolUse` | `POST /workspaces/{workspace_id}/tool/use` |
| project compiler pin | `ToolchainManagementAdapter.pinManagedCompiler()` | `toolPin` | `POST /workspaces/{workspace_id}/tool/pin` |
| clear project compiler pin | `ToolchainManagementAdapter.clearPinnedCompiler()` | `toolClearPin` | `POST /workspaces/{workspace_id}/tool/clear-pin` |
| dependency fetch | `DependencySourceAdapter.fetchDependencies()` | `fetchDependencies` | `POST /workspaces/{workspace_id}/dependencies/fetch` |
| dependency vendor | `DependencySourceAdapter.vendorDependencies()` | `vendorDependencies` | `POST /workspaces/{workspace_id}/dependencies/vendor` |
| run active document | `ExecutionAdapter.runActiveDocument()` when target lane is `run` | `runWorkflow` | `POST /workspaces/{workspace_id}/execution/run` |
| build active document | `ExecutionAdapter.runActiveDocument()` when target lane is `build` | `buildWorkflow` | `POST /workspaces/{workspace_id}/execution/build` |
| test active document | `ExecutionAdapter.runActiveDocument()` when target lane is `test` | `testWorkflow` | `POST /workspaces/{workspace_id}/execution/test` |
| pack artifact | `DeploymentAdapter.packProject()` | `packProject` | `POST /workspaces/{workspace_id}/deployment/pack` |
| publish preflight | `DeploymentAdapter.preparePublish()` | `preparePublish` | `POST /workspaces/{workspace_id}/deployment/preflight` |
| publish artifact | `DeploymentAdapter.publishToRegistry()` | `publishToRegistry` | `POST /workspaces/{workspace_id}/deployment/publish` |

`RuntimeEventAdapter` does not call a separate hosted route in `v1`; it consumes `runtime_events` emitted by the execution envelopes documented in `runWorkflow`, `buildWorkflow`, and `testWorkflow`.

## Frontend Request Body Summary

`styio-view` binds to these request fields when it calls the hosted control plane:

| Operation | Required request fields consumed by frontend | Optional request fields consumed by frontend |
|-----------|----------------------------------------------|---------------------------------------------|
| `openWorkspace` | `workspace_root`, `platform` | `manifest_path` |
| `toolInstall` | `styio_binary_path` | none |
| `toolUse` | `compiler_version` | `channel` |
| `toolPin` | `compiler_version` | `channel` |
| `toolClearPin` | empty JSON object | none |
| `fetchDependencies` | none | `locked`, `offline` |
| `vendorDependencies` | none | `output_path`, `locked`, `offline` |
| `runWorkflow` | `active_file_path`, `document_text` | `package_name`, `target_name`, `target_kind` |
| `buildWorkflow` | `active_file_path`, `document_text` | `package_name`, `target_name`, `target_kind` |
| `testWorkflow` | `active_file_path`, `document_text` | `package_name`, `target_name`, `target_kind` |
| `packProject` | none | `package_name`, `output_path` |
| `preparePublish` | none | `package_name`, `output_path` |
| `publishToRegistry` | `registry_root` | `package_name`, `output_path` |

Path parameter `workspace_id` is required for every hosted route except `openWorkspace`.

## Workspace Envelope Fields Consumed By Frontend

When `ProjectGraphAdapter` runs in hosted mode, the frontend consumes the `workspace` envelope alongside the project graph payload. The frontend contract depends on:

1. `workspaceId`
2. `schemaVersion`
3. `ownerRef`
4. `status`
5. `entryUrl`
6. `createdAt`
7. `lastActiveAt`
8. `retentionDays`
9. `exportState`
10. `closedAt`
11. `retentionDeadline`
12. `coreFileExportUrl`
13. `coreFileExportExpiresAt`

These fields are part of the hosted consumer contract even when some deployments leave the optional timestamps or export URLs empty.

## Execution Envelope Fields Consumed By Frontend

Hosted execution is a single response-envelope contract. `styio-view` does not rely on a separate event stream route in `v1`.

The frontend consumes:

1. top-level `returncode`
2. top-level `message`
3. top-level `stdout`
4. top-level `stderr`
5. `payload` on success or `error_payload` on command-level failure
6. execution `payload.session_id`
7. execution `payload.runtime_events[]`
8. execution `payload.diagnostics[]`
9. execution `payload.stdout`
10. execution `payload.stderr`

`runtime_events[]` entries are consumed as structured envelopes with:

1. `schemaVersion` or `schema_version`
2. `sessionId` or `session_id`
3. `sequence`
4. `timestamp`
5. `eventKind` or `event_kind`
6. `origin`
7. `payload`

## Workflow Entry Points

For independent frontend/backend development, use:

1. `openapi.json` for route, schema, and example truth
2. `workflows.arazzo.json` for multi-operation flows such as bootstrap, toolchain install/use/pin, dependency+execution loops, and publish flows
3. this consumer note for the exact request and envelope fields the frontend binds to

## Frontend Rules

1. Frontend code must not call undocumented hosted routes.
2. Frontend code must not infer backend-only state from filesystem structure when the hosted API already publishes it.
3. `project-graph`, `execution`, `deployment`, and `tool` payload handling must stay compatible with the published examples and envelope semantics.
4. Any breaking change to this route set or its required fields requires a new hosted contract version, not an in-place rewrite.
5. Frontend and backend teams should discuss new flows by adding or updating Arazzo workflows, not by relying on issue-thread prose alone.
