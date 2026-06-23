# Execution Overlay Hardening Audit Shard

**Purpose:** Record execution overlay isolation findings from the parallel external audit pass.

**Last updated:** 2026-04-22

**Date:** 2026-04-22

**Scope:** `frontend/vityo_app/lib/src/backend_toolchain/execution_adapter_io.dart` execution overlay isolation.

## Findings Addressed

| Finding | Severity | Status | Remediation |
|---------|----------|--------|-------------|
| VIEW-AUD-002 | High | Remediated in owned scope | Replaced overlay symlink mirroring with a bounded recursive file snapshot. Execution tools now write into copied files, not links back to the source workspace. |
| VIEW-AUD-004 | Medium | Remediated in owned scope | Reworked root containment and overlay path mapping to resolve symlinks before comparing roots. Symlink escape paths no longer pass by lexical prefix alone. |

## Implementation Notes

- Overlay snapshots skip symlink entries instead of reproducing them in the execution directory.
- Snapshot preparation has entry and byte limits and returns a blocked execution session on overlay preparation failure.
- Overlay diagnostic/runtime path normalization now uses resolved containment checks so paths created through overlay symlinks do not normalize back into the source workspace.

## Verification

- `flutter test test/execution_adapter_test.dart`
- `flutter analyze lib/src/backend_toolchain/execution_adapter_io.dart test/execution_adapter_test.dart`

Focused coverage added:

- Non-active source files remain unchanged when the tool writes to the corresponding execution overlay path.
- Symlink entries that point outside the workspace are omitted from the overlay and cannot mutate their targets through execution.
- Project execution blocks changed active files whose lexical workspace paths resolve through symlinks outside the workspace root.

## Remaining Risks

- Large workspaces may now hit the overlay snapshot caps and receive a blocked execution session until a more selective snapshot or read-only filesystem model is introduced.
- Symlinked workspace entries are intentionally omitted from execution snapshots; projects that require symlinked inputs need an explicit allowlisted dereference policy before support is restored.
