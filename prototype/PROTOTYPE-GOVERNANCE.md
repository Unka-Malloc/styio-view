# Prototype Governance

**Purpose:** Define the repo-local rules for keeping `prototype/` high-fidelity editor surfaces discoverable, owned, and testable without adding downstream branch Rulesets.

**Last updated:** 2026-07-26

## Surface Classes

1. `canonical`: the current editor workflow that may carry product behavior. As of 2026-07-26 there is no active canonical entry: the JavaScript prototype is archived and the Flutter app (`products/vityo_app`) is the default client.
2. `style-experiment`: a standalone visual direction sample. It may inform Theme / UX, but it cannot introduce product contracts or workspace mutation semantics.
3. `draft`: an archived surface that is kept for reference only. It is no longer maintained, must not gain new product behavior, and keeps its last known validation route documented for archaeology. Today this is `editor.html`.

## Required Rules

1. Every top-level `prototype/*.html` file must be listed in `prototype-manifest.json`.
2. At most one manifest entry may have `status: "canonical"`; when one exists it must match `canonical_entry`. When the surface has no active canonical entry (for example after archiving), `canonical_entry` must be `null` and no entry may be `canonical`.
3. Canonical entries must use `Shell / Editor` ownership and must be covered by `npm run selftest:editor`.
4. Style experiment entries must declare an owner and validation route; when they graduate into product behavior, move the behavior through the active canonical client and add automated coverage.
5. Draft entries must declare an owner and the validation route that was last known to pass; they receive no new feature work.
6. New workspace or server behavior must keep the `dev_server.py` security invariants: localhost binding, Host allowlist, API credential checks, same-origin mutation, default-off mutation, and workspace-limited file reads.
7. Generated or local-only payloads stay ignored: `node_modules/`, `__pycache__/`, `.artifacts/`, and local workspace runtime state must not become tracked source.

## Gate

Run:

```bash
npm run governance
npm run selftest:editor
```

`./scripts/checkpoint-health.sh` runs both commands as part of the repository checkpoint floor.
