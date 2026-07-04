# Checkpoint Health

**Purpose:** Define the repository-wide build/test health entrypoint for `Vityo` so CI and checkpoint delivery can call one script instead of wiring Flutter and prototype verification inline.

**Last updated:** 2026-06-19

## Command

```bash
./scripts/checkpoint-health.sh
```

## What It Runs

1. `flutter analyze` in `frontend/vityo_app`
2. `python3 -m unittest tests.test_repo_hygiene_gate`
3. `python3 scripts/project-coverage-gate.py --python-fail-under 95 --flutter-fail-under 85 --flutter-dir frontend/vityo_app`, which runs the Python tooling coverage gate and `flutter test --coverage`
4. `python3 scripts/release-readiness-gate.py --skip-build`
5. `./scripts/language-fixture-gate.sh --flutter-dir frontend/vityo_app`
6. `npm run governance` in `prototype/`
7. `npm run selftest:editor` in `prototype/` with the focused editor URL pinned to port `4180`

The repository keeps its native Flutter, Python, and npm-based tooling, but callers must continue to use this outer health entrypoint. CI installs `coverage.py` before the health gate so the Python coverage floor and Flutter LCOV floor are both enforced.

The language fixture gate wrapper defaults to the parser-backed CI roots `test/fixtures/language_service` and `test/fixtures/styio_language/syntax_contract`. Pass one or more `--fixture-root` values to scan a broader fixture set intentionally.

Set `PYTHON_BIN` to run the Python gates through a prepared virtual environment; it defaults to `python3`. GitHub Actions uploads `.coverage` and `frontend/vityo_app/coverage/lcov.info` as `vityo-coverage-reports-linux`, `vityo-coverage-reports-windows`, or `vityo-coverage-reports-macos` after each platform gate. The separate `project-coverage-gate` workflow runs only the Python plus Flutter coverage gate and uploads the same LCOV source as `vityo-project-coverage`.
