# Nightly Subbranch Merge Report

**Date:** 2026-06-24
**Purpose:** Record the consolidation of all non-nightly subbranches into `nightly`.

**Last updated:** 2026-06-24

## Remote Branches at Start

- origin/codex/styio-view-delivery-closure
- origin/coverage/project-coverage-gate-20260619205915
- origin/feature/vityo-ide-capability-upgrade
- origin/nightly
- upstream/ai-dev
- upstream/main
- upstream/nightly
- upstream/stable

## Nightly Start SHA

c7484c9b8e97fd0eb39f73893891f5680763123e

## Merge Order

1. coverage/project-coverage-gate-20260619205915
2. codex/styio-view-delivery-closure
3. feature/vityo-ide-capability-upgrade

## 1. Coverage Branch Merge

**Status:** MERGED with minor conflict resolution
**Branch:** origin/coverage/project-coverage-gate-20260619205915
**Stats:** 91 files, +18,037/-189

### Conflict Files

| File | Resolution |
|------|-----------|
| `frontend/vityo_app/test/workspace_code_lens_test.dart` | Accepted coverage branch (theirs) — adds 3 test cases for query helpers, non-function lenses, target mismatches, and glob forms. Nightly already had first 2 tests; coverage added more comprehensive coverage. |
| `frontend/vityo_app/test/vityo_app_smoke_test.dart` | Accepted coverage branch (theirs) — adds extensive bottom-surface tab navigation tests including document links, highlights, code lenses, declarations, definitions, type hierarchy, outline, symbols, references, call hierarchy, search, problems, code actions, and rename. |

### Key Observations

- Nearly all files (88/91) from the coverage branch already existed in nightly — the branch is largely already absorbed.
- The 2 conflicted files were test files where coverage added test bodies that nightly had as placeholders.
- `toolchain/maintenance-tools.json` was added (new file from coverage).
- Fixture rename `vityo_ide_2026_05.json` → `ide_syntax_contract.json` was already in nightly.
- Updated `docs/teams/DOCS-DELIVERY-RUNBOOK.md` last-updated date and `docs/teams/DOC-STATS.md` counts.

### Validation

| Gate | Result |
|------|--------|
| repo-hygiene-gate.py --mode tracked | PASS |
| docs-index.py --write | PASS |
| docs-index.py --check | PASS |
| team-docs-gate.py | PASS |
| docs-audit.py | PASS |
| Python unit tests (101 tests) | PASS |
| Flutter analyze / test | SKIPPED (Flutter/Dart not available in local env; must run in CI) |

## 2. Codex Branch Merge

**Status:** PENDING

## 3. Feature Branch Merge

**Status:** PENDING

## High-Risk Area Status

TBD after all merges complete.

## Validation

TBD after all merges complete.
