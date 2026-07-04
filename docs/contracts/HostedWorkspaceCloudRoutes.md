# HostedWorkspaceCloudRoutes

**Purpose:** Freeze the frontend-facing hosted workspace cloud routes that `Vityo` consumes from the `pafio` hosted control plane. This contract documents the route set, request/response envelope invariants, lifecycle state machine, security boundaries, and consumer-side rules so that frontend and backend can ship independently against a fixed contract.

**Last updated:** 2026-06-29

## 1. Owned Artifacts

### 1.1 HostedWorkspaceRecord

The canonical record shape is defined in:
- `docs/specs/HOSTED-WORKSPACE-RECORD-SCHEMA.md` (schema baseline)
- `frontend/vityo_app/lib/src/view_ide/backend_toolchain/project_graph_contract.dart` (Dart snapshot: `HostedWorkspaceRecordSnapshot`, lines 183-209)
- `docs/external/for-pafio/Pafio-Hosted-Control-Plane-Contract.md` (consumer-side handoff envelope, section "Workspace Envelope Fields Consumed By Frontend")

The record MUST contain:
1. `workspaceId: string`
2. `schemaVersion: string`
3. `ownerRef: string`
4. `status: enum { provisioning, active, closing, pendingDeletion, deleted }`
5. `entryUrl: string`
6. `createdAt: datetime`
7. `lastActiveAt: datetime`
8. `retentionDays: integer` (default 7)
9. `exportState: enum { notRequested, preparing, ready, expired }`

Optional fields:
1. `runtimeRef?: string`
2. `region?: string`
3. `closedAt?: datetime`
4. `retentionDeadline?: datetime`
5. `coreFileExportUrl?: string`
6. `coreFileExportExpiresAt?: datetime`
7. `warningAcknowledgedAt?: datetime`

### 1.2 Cloud Route Set

Base path: `/api/styio-hosted/v1`

Every route except `openWorkspace` is scoped under `workspaces/{workspace_id}`.

| Method | Route | operationId | Adapter lane |
|--------|-------|-------------|--------------|
| POST | `/workspaces/open` | `openWorkspace` | ProjectGraphAdapter first load |
| GET | `/workspaces/{workspace_id}/project-graph` | `projectGraph` | ProjectGraphAdapter refresh |
| POST | `/workspaces/{workspace_id}/tool/install` | `toolInstall` | ToolchainManagementAdapter.installManagedCompiler |
| POST | `/workspaces/{workspace_id}/tool/use` | `toolUse` | ToolchainManagementAdapter.useManagedCompiler |
| POST | `/workspaces/{workspace_id}/tool/pin` | `toolPin` | ToolchainManagementAdapter.pinManagedCompiler |
| POST | `/workspaces/{workspace_id}/tool/clear-pin` | `toolClearPin` | ToolchainManagementAdapter.clearPinnedCompiler |
| POST | `/workspaces/{workspace_id}/dependencies/fetch` | `fetchDependencies` | DependencySourceAdapter.fetchDependencies |
| POST | `/workspaces/{workspace_id}/dependencies/vendor` | `vendorDependencies` | DependencySourceAdapter.vendorDependencies |
| POST | `/workspaces/{workspace_id}/execution/run` | `runWorkflow` | ExecutionAdapter.runActiveDocument (run lane) |
| POST | `/workspaces/{workspace_id}/execution/build` | `buildWorkflow` | ExecutionAdapter.runActiveDocument (build lane) |
| POST | `/workspaces/{workspace_id}/execution/test` | `testWorkflow` | ExecutionAdapter.runActiveDocument (test lane) |
| POST | `/workspaces/{workspace_id}/deployment/pack` | `packProject` | DeploymentAdapter.packProject |
| POST | `/workspaces/{workspace_id}/deployment/preflight` | `preparePublish` | DeploymentAdapter.preparePublish |
| POST | `/workspaces/{workspace_id}/deployment/publish` | `publishToRegistry` | DeploymentAdapter.publishToRegistry |

### 1.3 Document Routes

These routes extend the main route set and are consumed by `HostedWorkspaceDocumentStore`:

| Method | Route | operationId | Frontend class |
|--------|-------|-------------|----------------|
| POST | `/workspaces/{workspace_id}/documents/load` | `loadDocument` | HostedWorkspaceDocumentStore.loadDocument |
| POST | `/workspaces/{workspace_id}/documents/save` | `saveDocument` | HostedWorkspaceDocumentStore.saveDocument |

### 1.4 Lifecycle Cloud Routes (projected, not yet published)

These routes are referenced by `HostedWorkspaceLifecycle.retryEndpointPlanFor()` and marked as `published: false`:

| Method | Route | action kind |
|--------|-------|-------------|
| GET | `/hosted/workspaces/{workspace_id}/project-graph` | `retryConnect`, `refreshWorkspace` |
| POST | `/hosted/workspaces/{workspace_id}/reopen` | `reopenWorkspace` |
| POST | `/hosted/workspaces/{workspace_id}/core-files/export` | `exportCoreFiles` |

Source: `frontend/vityo_app/lib/src/view_ide/workspace/hosted_workspace_lifecycle.dart`, method `retryEndpointPlanFor()`.

## 2. Product Boundaries

### 2.1 What the cloud route set owns

1. Workspace session lifecycle: open, provision, close, retention deadline, deletion.
2. Remote project graph access (read-only snapshot, not filesystem traversal).
3. Managed compiler install, activate, pin, clear-pin.
4. Dependency fetch and vendor (remote execution, not local cache enumeration).
5. Execution compile/run/test (single response envelope, not streaming event channel).
6. Deployment pack, preflight, publish to registry.
7. Document load/save with revision tracking.
8. Core-file export generation and signed-URL delivery.

### 2.2 What the cloud route set does NOT own

1. Local filesystem traversal or workspace file tree browsing (prototype dev server owns this).
2. Real-time event streaming for runtime surface / debug console (consumes execution envelope `runtime_events[]` but does not provide an independent event stream route).
3. Local execution or FFI compilation (FFI Adapter owns this).
4. Profile sync, theme config, or AI agent panel (separate subsystems).
5. Build artifact caching or incremental compilation state.

### 2.3 Invariant: Adapter parity

Every cloud route has a semantic equivalent in the CLI Adapter route family. The product semantics MUST be identical; differences are limited to transport (HTTP vs local process) and authorization environment (bearer token vs local shell). Source: `docs/external/for-pafio/Pafio-Hosted-Control-Plane-Contract.md` and `docs/contracts/DeploymentAdapter.md` section 4 rule 4.

## 3. Route Invariants

### 3.1 Base URL normalization

1. Base URL is read from `VITYO_HOSTED_URL` env var (or `String.fromEnvironment('VITYO_HOSTED_URL')` for web).
2. MUST be absolute `https`; `http` allowed only for loopback (localhost / 127.0.0.1 / ::1).
3. MUST NOT include credentials, query string, or fragment.
4. MUST NOT contain relative path segments (`.` or `..`).
5. Web fallback: `window.location.origin + '/api/styio-hosted/v1'`.

Source: `frontend/vityo_app/lib/src/view_ide/backend_toolchain/hosted_control_plane_io.dart`, `_normalizeHostedBaseUrl()`.

### 3.2 Route segment validation

Every route segment is validated before URL construction:
1. MUST NOT be empty.
2. MUST NOT be `.` or `..`.
3. MUST NOT contain `/` or `\`.
4. Path construction uses validated `Uri` path segments, never string concatenation.

Source: `_validateRouteSegments()` in the same IO file, line referenced from `VIEW-AUD-011`.

### 3.3 Authentication invariant

1. Every request (except open workspace bootstrap) targets a `{workspace_id}`-scoped route.
2. Bearer token from `VITYO_HOSTED_TOKEN` is required.
3. `Authorization: Bearer ...` header is sent on every request.
4. `Accept: application/json` header is sent.
5. Redirects are disabled; auth is never forwarded through redirect chains.

Source: hosted-control-plane-client-hardening.md finding `VIEW-AUD-003`.

### 3.4 Timeout and response bounds

1. Request timeout from `VITYO_HOSTED_TIMEOUT_MS` (default 15000 ms).
2. Max response bytes from `VITYO_HOSTED_MAX_RESPONSE_BYTES` (default 1048576 = 1 MiB).
3. Both declared `contentLength` and streamed chunks are checked against the max response byte limit.

### 3.5 Response envelope invariant

Every hosted route returns a JSON object envelope consumed by the frontend with these fields:

Top-level:
1. `returncode: int` (optional, type-checked)
2. `message: string` (optional, type-checked)
3. `stdout: string` (optional, type-checked)
4. `stderr: string` (optional, type-checked)
5. `payload: object` (optional, on success)
6. `error_payload: object` (optional, on command-level failure)
7. `workspace: object` (optional, workspace envelope)

Execution `payload` sub-structure:
1. `session_id: string`
2. `runtime_events[]: array`
3. `diagnostics[]: array`
4. `stdout: string`
5. `stderr: string`

Each `runtime_event` entry:
1. `schemaVersion` or `schema_version: string`
2. `sessionId` or `session_id: string`
3. `sequence: integer`
4. `timestamp: string`
5. `eventKind` or `event_kind: string`
6. `origin: string`
7. `payload: object`

Source: `docs/external/for-pafio/Pafio-Hosted-Control-Plane-Contract.md` and `frontend/vityo_app/lib/src/view_ide/backend_toolchain/hosted_control_plane_io.dart` `_validateResponseEnvelope()`.

### 3.6 Non-negotiable response rules

1. Non-2xx status codes MUST produce a failure with status message, never silent empty state.
2. Non-JSON response bodies MUST produce a failure, never silent decode.
3. Non-object JSON bodies MUST produce a failure.
4. Malformed optional envelope fields MUST produce a typed failure, never a silent type coercion.

Source: hosted-control-plane-client-hardening.md findings `VIEW-AUD-007`.

## 4. Success / Blocked / Recovery States

### 4.1 Workspace lifecycle state machine

```
provisioning --> active --> closing --> pendingDeletion --> deleted
                  |                          |
                  +-- (reopen) <--------------+
                  +-- (export core files) ----> ready/expired
```

1. `provisioning`: Workspace is being set up; not ready for use.
2. `active`: Workspace is operational; all routes accept requests.
3. `closing`: User-initiated close in progress; UI must show clear-confirmation warning and export entry before transitioning to this state.
4. `pendingDeletion`: Workspace closed; `closedAt` and `retentionDeadline` required. Default retention is 7 days. User may reopen to return to `active`.
5. `deleted`: Workspace destroyed; `entryUrl` MUST be invalid. No recovery possible.

Source:
- `docs/specs/HOSTED-WORKSPACE-RECORD-SCHEMA.md` section 5.
- `docs/adr/ADR-0015-uninstall-reclamation-and-hosted-workspace-retention.md`.
- `frontend/vityo_app/lib/src/view_ide/backend_toolchain/project_graph_contract.dart` enums `HostedWorkspaceStatus` and `HostedWorkspaceExportState`.

### 4.2 Export state machine

```
notRequested --> preparing --> ready --> expired
                  |
                  +--> (error) --> notRequested (retry)
```

1. `notRequested`: No export has been initiated.
2. `preparing`: Export is being generated by backend; UI shows preparing indicator.
3. `ready`: Export is available; `coreFileExportUrl` and `coreFileExportExpiresAt` MUST be populated.
4. `expired`: Signed URL has expired; user must initiate a new export.

### 4.3 Adapter-level status (blocked)

Every adapter route MUST return exactly one of: `succeeded`, `failed`, `blocked`, or `running`.

1. `succeeded`: Operation completed; payload contains structured result.
2. `failed`: Operation completed with errors; diagnostics and/or error_payload contain details.
3. `blocked`: Route is not available (adapter not deployed, feature not implemented, or preconditions not met); response includes a clear human-readable reason.
4. `running`: Operation is in progress (future: polling or async workflows; currently all routes are synchronous request-response).

Source: `docs/contracts/ExecutionAdapter.md` section 2, rule 3.

### 4.4 Connector parity report

When a hosted workspace record exists, the frontend generates a `HostedBackendConnectorParityReport` with these checks:

1. `control-plane`: Hosted control plane connector availability.
2. `document-store`: Hosted document store connector availability.
3. `backend-reachability`: Hosted backend route reachability.
4. `entry-url`: Workspace entry URL presence.

Based on these checks, the report status is one of:
- `ready`: All required checks pass.
- `unavailable`: No hosted workspace record at all.
- `degraded`: Some required checks fail but recovery actions exist.
- `expired`: Workspace retention deadline has passed.

Source: `frontend/vityo_app/lib/src/view_ide/workspace/hosted_workspace_lifecycle.dart`.

### 4.5 Recovery actions

The lifecycle model defines these recovery endpoint plans:

| Action kind | Method | Route | Published |
|-------------|--------|-------|-----------|
| `retryConnect` | GET | `/hosted/workspaces/{id}/project-graph` | yes |
| `refreshWorkspace` | GET | `/hosted/workspaces/{id}/project-graph` | yes |
| `reopenWorkspace` | POST | `/hosted/workspaces/{id}/reopen` | no (projected) |
| `exportCoreFiles` | POST | `/hosted/workspaces/{id}/core-files/export` | no (projected) |
| `openSettings` | OPEN | `settings://hosted-backend?workspaceId={id}` | yes |

## 5. Security / Redaction Boundaries

### 5.1 Transport security

1. Base URL MUST be `https` in production; `http` only for loopback local development.
2. Bearer token sent on every request; never exposed in URL query or fragment.
3. Redirects disabled; bearer token never forwarded.
4. Credentials, query strings, and fragments rejected at the base URL level.

### 5.2 Response redaction

1. `coreFileExportUrl` contains a time-limited signed URL; MUST expire after a backend-defined window.
2. `coreFileExportExpiresAt` communicates the expiry time to the UI; UI MUST NOT cache or redistribute the URL.
3. Response size bounded by configurable maximum; oversized responses produce a typed failure, not partial decode.

### 5.3 Workspace entry URL invalidation

1. When `status = deleted`, `entryUrl` MUST be invalid (HTTP 404 or 410).
2. The UI MUST NOT attempt to navigate to a deleted workspace's entry URL.

### 5.4 Token source

1. The token source is `VITYO_HOSTED_TOKEN` environment variable only.
2. Rotation, refresh, and secure platform credential storage are NOT modeled in this contract; they are a known residual risk (hosted-control-plane-client-hardening.md).

### 5.5 Web-specific risk

1. The web (`_WebHostedControlPlaneClient`) transport does not implement bearer auth, timeout, or response size limits in the same hardened manner as the IO client.
2. The web client relies on the origin server's cookie/session mechanism when deployed on the same origin.
3. This asymmetry is a known residual risk documented in hosted-control-plane-client-hardening.md.

## 6. Downstream Consumers

### 6.1 HostedControlPlaneClient interface

Abstract class at `frontend/vityo_app/lib/src/view_ide/backend_toolchain/hosted_control_plane.dart`.

Two implementations:
1. **IO client** (`hosted_control_plane_io.dart`): Uses `dart:io` `HttpClient`; supports bearer auth, timeout, response size limiting, envelope validation. Used on desktop/mobile native targets.
2. **Web client** (`hosted_control_plane_web.dart`): Uses `dart:js_interop` + `web` package `fetch`; no bearer auth (relies on origin cookies); no timeout or size limiting. Used on web target only.

Platform target selection is by conditional import:
```dart
import 'hosted_control_plane_web.dart'
    if (dart.library.io) 'hosted_control_plane_io.dart'
    as platform;
```

### 6.2 Adapter consumers

Each adapter contract consumes the cloud routes as follows:

| Contract | Cloud route consumed | Contract file |
|----------|---------------------|---------------|
| ProjectGraphAdapter | `openWorkspace`, `projectGraph` | `docs/contracts/ProjectGraphAdapter.md` |
| ToolchainManagementAdapter | `toolInstall`, `toolUse`, `toolPin`, `toolClearPin` | `docs/contracts/ToolchainManagementAdapter.md` |
| DependencySourceAdapter | `fetchDependencies`, `vendorDependencies` | `docs/contracts/DependencySourceAdapter.md` |
| ExecutionAdapter | `runWorkflow`, `buildWorkflow`, `testWorkflow` | `docs/contracts/ExecutionAdapter.md` |
| DeploymentAdapter | `packProject`, `preparePublish`, `publishToRegistry` | `docs/contracts/DeploymentAdapter.md` |
| RuntimeEventAdapter | (consumes `runtime_events[]` from execution payload) | `docs/contracts/RuntimeEventAdapter.md` |

### 6.3 HostedWorkspaceDocumentStore

File: `frontend/vityo_app/lib/src/view_ide/workspace/hosted_workspace_document_store.dart`

Consumes:
- `POST /workspaces/{id}/documents/load` with `{ path }`
- `POST /workspaces/{id}/documents/save` with `{ path, document_text, revision }`

Document deletion is explicitly `UnsupportedError` in the hosted path.

### 6.4 HostedWorkspaceFileSystemProvider

File: `frontend/vityo_app/lib/src/view_ide/workspace/hosted_workspace_file_system_provider.dart`

Consumes the same hosted document load/save routes as `HostedWorkspaceDocumentStore` and exposes:
- `vityo-hosted://{workspace_id}/{document_path}` routing through `FileSystemProviderRouter`.
- document read/write mapped to hosted load/save.
- structured unsupported failures for unpublished hosted file-system operations such as delete/list/watch.

### 6.5 HostedWorkspaceLifecycle

File: `frontend/vityo_app/lib/src/view_ide/workspace/hosted_workspace_lifecycle.dart`

Consumes the `HostedWorkspaceRecordSnapshot` from the project graph and computes:
- `HostedWorkspaceClosePlan`: close confirmation requirements, export state, core file paths.
- `HostedWorkspacePendingDeletionPlan`: retention calculation, deadline, remaining time, expiry check.
- `HostedBackendConnectorParityReport`: connector availability checks and recovery actions.

## 7. Single Implementation Path

### 7.1 Contract hierarchy

1. **Source of truth**: Backend-owned OpenAPI spec at `styio-pafio/contracts/hosted-control-plane/v1/openapi.json`.
2. **Consumer handoff**: `docs/external/for-pafio/Pafio-Hosted-Control-Plane-Contract.md` -- maps routes to frontend method names, request fields, envelope fields.
3. **Frontend interface**: `HostedControlPlaneClient` abstract class -- one method per operationId.
4. **Transport implementations**: IO client (hardened, native) and Web client (same routes, lighter transport).
5. **Hosted file-system provider**: `HostedWorkspaceFileSystemProvider` -- `vityo-hosted://` URI routing and hosted document read/write.
6. **Lifecycle model**: `HostedWorkspaceLifecycle` -- state machine, close plan, deletion plan, connector parity.

### 7.2 Rules for adding new routes

1. Add the operation to the backend's `openapi.json` and `workflows.arazzo.json` first.
2. Update the consumer handoff document with the new route, request fields, and envelope fields.
3. Add the method to `HostedControlPlaneClient` abstract class.
4. Implement in both IO and Web clients.
5. Add the route to the relevant adapter contract's hosted route mapping.
6. Add lifecycle recovery endpoint plan if the new route participates in error recovery.

### 7.3 Breaking changes protocol

1. Any breaking change to the route set, required fields, or envelope shape requires a new contract version (new `schemaVersion`), not an in-place rewrite.
2. Frontend and backend teams MUST coordinate new flows through Arazzo workflow additions, not issue-thread prose alone.
3. The consumer handoff document MUST be updated atomically with the backend contract package.

Source: `docs/external/for-pafio/Pafio-Hosted-Control-Plane-Contract.md` frontend rules.

## 8. Verification Evidence

### 8.1 Contract files (backend-owned, consumed by frontend)

- `styio-pafio/contracts/hosted-control-plane/v1/openapi.json`
- `styio-pafio/contracts/hosted-control-plane/v1/workflows.arazzo.json`
- `styio-pafio/contracts/hosted-control-plane/v1/hosted-control-plane.contract.json`
- `styio-pafio/contracts/hosted-control-plane/v1/hosted-control-plane.examples.json`
- `styio-pafio/contracts/hosted-control-plane/v1/redocly.yaml`

Referenced in `docs/external/for-pafio/Pafio-Hosted-Control-Plane-Contract.md`.

### 8.2 Frontend interface and implementation files

- `frontend/vityo_app/lib/src/view_ide/backend_toolchain/hosted_control_plane.dart` (abstract interface)
- `frontend/vityo_app/lib/src/view_ide/backend_toolchain/hosted_control_plane_io.dart` (IO implementation, ~665 lines)
- `frontend/vityo_app/lib/src/view_ide/backend_toolchain/hosted_control_plane_web.dart` (web implementation)
- `frontend/vityo_app/lib/src/view_ide/workspace/hosted_workspace_lifecycle.dart` (lifecycle model, ~557 lines)
- `frontend/vityo_app/lib/src/view_ide/workspace/hosted_workspace_document_store.dart` (document store)
- `frontend/vityo_app/lib/src/view_ide/workspace/hosted_backend_retry_executor.dart` (retry executor)
- `frontend/vityo_app/lib/src/view_ide/backend_toolchain/project_graph_contract.dart` (`HostedWorkspaceRecordSnapshot`, enums)

### 8.3 Test evidence

- `frontend/vityo_app/test/hosted_control_plane_client_test.dart` (end-to-end hosted adapter contract path with bearer auth)
- `frontend/vityo_app/test/hosted_control_plane_io_hardening_test.dart` (token requirement, auth/header, URL construction, non-2xx, timeout, response-size, non-JSON, non-object, malformed envelope)
- `frontend/vityo_app/test/hosted_workspace_lifecycle_test.dart` (lifecycle state computing)
- `frontend/vityo_app/test/hosted_workspace_lifecycle_golden_test.dart` (golden lifecycle tests)
- `frontend/vityo_app/test/hosted_payload_codec_test.dart`
- `frontend/vityo_app/test/hosted_execution_codec_test.dart`
- `frontend/vityo_app/test/hosted_product_workflow_test.dart`
- `frontend/vityo_app/test/hosted_runtime_execution_test.dart`
- `frontend/vityo_app/test/hosted_workspace_document_store_test.dart`

### 8.4 Audit evidence

- `docs/audit/agent-findings/hosted-control-plane-client-hardening.md` (findings VIEW-AUD-003, VIEW-AUD-007, VIEW-AUD-011; all remediated)

### 8.5 Supporting documents

- `docs/specs/HOSTED-WORKSPACE-RECORD-SCHEMA.md` (record schema baseline)
- `docs/adr/ADR-0015-uninstall-reclamation-and-hosted-workspace-retention.md` (lifecycle decisions)
- `docs/external/for-pafio/Pafio-Hosted-Control-Plane-Contract.md` (consumer handoff)
- `docs/contracts/ExecutionAdapter.md` (execution envelope, hosted route mapping)
- `docs/contracts/DeploymentAdapter.md` (deployment hosted route mapping)
- `docs/contracts/README.md` (contract rules: CLI / FFI / Cloud parity)
- `docs/plan/repository-delivery-convergence/Evidence.md` (hosted workspace export and retention flow milestones)
- `docs/specs/REPOSITORY-MAP.md` (Vityo-cloud future split boundary)
