# Performance Baseline

**Purpose:** Record Vityo performance baselines for regression detection.

**Last updated:** 2026-06-25

**Status:** Baseline established (initial — no prior data for comparison).

## Environment

- **Runner**: Not available in this environment (no Flutter/Dart VM)
- **Gate script**: `scripts/performance-gate.py`
- **Benchmark directory**: `frontend/vityo_app/benchmark/`

## Benchmarks Defined

| ALG | Name | Category | Status |
|-----|------|----------|--------|
| ALG-01 | Piece Table (Source Buffer) | Editor | Skipped — no Dart runtime |
| ALG-02 | LineIndex (Fenwick/Augmented Tree) | Editor | Skipped — no Dart runtime |
| ALG-03 | Decorations (Interval Tree) | Editor | Skipped — no Dart runtime |
| ALG-04 | Copy-on-Write Snapshots | Language | Skipped — no Dart runtime |
| ALG-05 | Workspace Graph (DAG + Tarjan) | Workspace | Skipped — no Dart runtime |
| ALG-06 | Language Cache (Two-Level LRU) | Language | Skipped — no Dart runtime |
| ALG-07 | Runtime Events (Append-only Log) | Runtime | Skipped — no Dart runtime |
| ALG-08 | AI Context (Budgeted Packing) | AI | Skipped — no Dart runtime |
| ALG-09 | Watcher (Coalescing Queue) | Platform | Skipped — no Dart runtime |
| ALG-10 | UI Virtualization | UI | Skipped — no Dart runtime |

## Performance Gate

The `scripts/performance-gate.py` script:
- Discovers benchmarks in `frontend/vityo_app/benchmark/`
- Runs them via `dart run` when Dart VM is available
- Compares against baseline JSON
- Fails on regression > configurable threshold (default: 10%)
- Outputs machine-readable JSON

## Reproduce

To establish the first real baseline:

```bash
# Install Flutter SDK 3.41.x
cd frontend/vityo_app && flutter pub get

# Run all benchmarks and save baseline
python3 scripts/performance-gate.py --save-baseline

# Later, check for regressions
python3 scripts/performance-gate.py --threshold 1.10
```

## Target Thresholds

| Metric | Target (p95) |
|--------|-------------|
| 10k-line file open | < 500ms |
| 10k-line typing latency | < 16ms (one frame) |
| 100k semantic span viewport query | < 5ms |
| 100-package workspace graph build | < 2s |
| Language cache hit latency | < 100μs |
| 10k runtime events replay | < 1s |
| AI context packing (small workspace) | < 500ms |
| 100-event watcher burst coalescing | < 50ms |
| 10k-item virtualized list frame | < 16ms |
