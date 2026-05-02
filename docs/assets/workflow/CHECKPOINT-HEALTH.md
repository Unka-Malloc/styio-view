# Checkpoint Health

**Purpose:** Define the repository-wide build/test health entrypoint for `styio-view` so CI and checkpoint delivery can call one script instead of wiring Flutter and prototype verification inline.

**Last updated:** 2026-05-02

## Command

```bash
./scripts/checkpoint-health.sh
```

## What It Runs

1. `flutter analyze` in `frontend/styio_view_app`
2. `flutter test` in `frontend/styio_view_app`
3. `npm run governance` in `prototype/`
4. `npm run selftest:editor` in `prototype/` with the focused editor URL pinned to port `4180`

The repository keeps its native Flutter and npm-based tooling, but callers must continue to use this outer health entrypoint.
