# Prototype Server Hardening Finding Shard

**Purpose:** Record prototype dev-server security findings from the parallel external audit pass.

**Last updated:** 2026-04-22

**Date:** 2026-04-22

**Scope:** `prototype/dev_server.py` local development security boundary.

**Related audit ID:** `VIEW-AUD-001`

**Status:** Remediated for the prototype dev-server boundary.

## Finding

The prototype dev server exposed local workspace and file-browser APIs without a local auth boundary. Before remediation, `/api/workspace`, `/api/browser/*`, and `POST /api/workspace/*` could list, read, create, overwrite, rename, delete, or retarget local workspace files from any process able to reach the loopback listener.

## Remediation

1. Kept the server bound to `127.0.0.1` and added `Host` allowlisting for `localhost`, `127.0.0.1`, and `::1` on the active dev-server port.
2. Added a per-process session credential. Static page responses issue `styio_dev_server_session` as `HttpOnly; SameSite=Strict`; all `/api/` routes now fail closed without that cookie or an explicit `X-Styio-Dev-Server-Token` / `Authorization: Bearer` token.
3. Added same-origin `Origin` enforcement for every `POST /api/` route.
4. Disabled all workspace mutation routes by default. Local writes now require `STYIO_DEV_SERVER_ENABLE_MUTATION=1` for the local dev-server session.
5. Limited `/api/browser/file` content reads to files inside the current workspace root, so authenticated local sessions cannot use the browser preview endpoint to read arbitrary UTF-8 files elsewhere on the machine.
6. Added `prototype/test_dev_server_security.py` to exercise missing-cookie denial, valid-cookie reads, workspace-limited file reads, Host rejection, Origin rejection, disabled mutation, enabled mutation, and invalid-origin denial over real HTTP.
7. Updated `prototype/README.md` with the local development security model and validation command.

## Validation

Run from repository root:

```bash
python3 -m unittest prototype/test_dev_server_security.py
```

Observed result on 2026-04-28: `Ran 9 tests ... OK`.

## Remaining Risks

1. An authenticated local editor session can still browse and read UTF-8 files selected through the prototype file browser. This is intentional for the local workspace picker, but it remains sensitive and should not be exposed beyond loopback.
2. When `STYIO_DEV_SERVER_ENABLE_MUTATION=1` is set, the prototype can still mutate files under the selected workspace root. That is now explicit local-dev opt-in rather than default behavior.
3. The session token is process-local unless `STYIO_DEV_SERVER_TOKEN` is supplied. Restarting the server invalidates existing static-page sessions.
