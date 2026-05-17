# Checkpoint Health

**Purpose:** Define the repository-wide build/test health entrypoint for `Vityo` so CI and checkpoint delivery can call one script instead of wiring Flutter and prototype verification inline.

**Last updated:** 2026-05-02

## Command

```bash
./scripts/checkpoint-health.sh
```

## What It Runs

1. `flutter analyze` in `frontend/vityo_app`
2. `python3 -m unittest tests.test_repo_hygiene_gate`
3. `flutter test` in `frontend/vityo_app`
4. `npm run governance` in `prototype/`
5. `npm run selftest:editor` in `prototype/` with the focused editor URL pinned to port `4180`

The repository keeps its native Flutter and npm-based tooling, but callers must continue to use this outer health entrypoint.
