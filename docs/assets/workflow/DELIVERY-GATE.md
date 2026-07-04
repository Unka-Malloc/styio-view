# Delivery Gate

**Purpose:** Define the common delivery-floor entrypoint for `Vityo` so contributors can run repository hygiene, the unified docs gate, external `styio-audit`, and checkpoint health through one command before checkpoint merge or branch delivery.

**Last updated:** 2026-06-19

## Command

Checkpoint delivery floor:

```bash
./scripts/delivery-gate.sh --mode checkpoint
```

Push or branch-delivery floor:

```bash
./scripts/delivery-gate.sh --mode push --base origin/main
```

Docs/process-only delivery:

```bash
./scripts/delivery-gate.sh --mode checkpoint --skip-health
```

Use `--audit-bin ../styio-audit/bin/styio-audit` to force a specific audit checkout. Use `--skip-audit` only when external audit is enforced by the separate required `styio-audit` check or for explicitly scoped docs/process recovery where external audit is run separately. The ecosystem CLI doc check runs by default as non-blocking evidence; reserve `--skip-ecosystem` for targeted recovery, not normal CI.

## What It Runs

1. `python3 scripts/repo-hygiene-gate.py`
2. `./scripts/docs-gate.sh`
3. external `styio-audit gate --project Vityo`
4. `./scripts/checkpoint-health.sh`, including the `95%` project coverage gate and release-readiness static checks for `toolchain/maintenance-tools.json`

The standalone `project-coverage-gate` GitHub Actions workflow is the direct coverage evidence lane. It runs `python3 scripts/project-coverage-gate.py --python-fail-under 95 --flutter-fail-under 85` and uploads the Flutter LCOV report without waiting on sibling repository build steps.

The `local-ci-gate` workflow mirrors this delivery floor on `ubuntu-latest`, `windows-latest`, and `macos-latest`. GitHub Rulesets for `nightly` must require `audit`, `styio-audit`, `local-ci-gate`, `windows-native`, and `macos-native`.
