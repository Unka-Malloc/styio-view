# Prototype Governance

**Purpose:** Define the repo-local rules for keeping `prototype/` high-fidelity editor surfaces discoverable, owned, and testable without adding downstream branch Rulesets.

**Last updated:** 2026-05-18

## Surface Classes

1. `canonical`: the current editor workflow that may carry product behavior. Today this is `editor.html`.
2. `style-experiment`: a standalone visual direction sample. It may inform Theme / UX, but it cannot introduce product contracts or workspace mutation semantics.

## Required Rules

1. Every top-level `prototype/*.html` file must be listed in `prototype-manifest.json`.
2. Exactly one manifest entry must have `status: "canonical"`, and it must match `canonical_entry`.
3. Canonical entries must use `Shell / Editor` ownership and must be covered by `npm run selftest:editor`.
4. Style experiment entries must declare an owner and validation route; when they graduate into product behavior, move the behavior through `editor.html` and add automated coverage.
5. New workspace or server behavior must keep the `dev_server.py` security invariants: localhost binding, Host allowlist, API credential checks, same-origin mutation, default-off mutation, and workspace-limited file reads.
6. Generated or local-only payloads stay ignored: `node_modules/`, `__pycache__/`, `.artifacts/`, and local workspace runtime state must not become tracked source.

## Gate

Run:

```bash
npm run governance
npm run selftest:editor
```

`./scripts/checkpoint-health.sh` runs both commands as part of the repository checkpoint floor.
