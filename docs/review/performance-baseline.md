# Performance Baseline

**Purpose:** Record Vityo performance baselines for regression detection.

**Last updated:** 2026-06-29

**Status:** Real benchmark baseline established. The local gate ran 10/10 benchmarks with no skipped benchmarks, no benchmark errors, and no regressions.

## Environment

- **Host:** Windows native shell
- **Runner:** Windows Python 3.10 with UTF-8 output and Dart from `T:\DevEnv\flutter\bin\cache\dart-sdk\bin`
- **Gate script:** `scripts/performance-gate.py --json`
- **Benchmark directory:** `frontend/vityo_app/benchmark/`
- **Gate result:** passed
- **Runner availability:** runner available, Dart available, Flutter not required for this benchmark set

## Benchmarks Measured

| ALG | Name | Category | Status | Representative p95 |
|-----|------|----------|--------|--------------------|
| ALG-01 | Piece Table (Source Buffer) | Editor | Passed | 10k-line open 6.506 ms; 100k-line open 122.470 ms; 10k random insert 0.826 ms |
| ALG-02 | LineIndex (Fenwick/Augmented Tree) | Editor | Passed | 100k offset lookup 0.013 ms; 100k affected-range update 4.548 ms; 100k rebuild 11.238 ms |
| ALG-03 | Decorations (Interval Tree) | Editor | Passed | 100k diagnostics viewport query 2.316 ms; 100k semantic viewport query 0.985 ms |
| ALG-04 | Copy-on-Write Snapshots | Language | Passed | 100k snapshot creation 80.839 ms; 100k atomic swap 0.000 ms |
| ALG-05 | Workspace Graph (DAG + Tarjan) | Workspace | Passed | 100-package build 0.206 ms; 1000-package dependency resolution 0.304 ms |
| ALG-06 | Language Cache (Two-Level LRU) | Language | Passed | cache hit latency 0.003 ms; invalidation overhead 0.007 ms |
| ALG-07 | Runtime Events (Append-only Log) | Runtime | Passed | 10k replay 0.067 ms; 100k replay 0.808 ms |
| ALG-08 | AI Context (Budgeted Packing) | AI | Passed | 10k context packing 0.019 ms; 10k budget clipping 1.357 ms |
| ALG-09 | Watcher (Coalescing Queue) | Platform | Passed | 10k burst handling 0.162 ms; 2000-event overflow detection 0.031 ms |
| ALG-10 | UI Virtualization | UI | Passed | 10k visible-items query 0.096 ms; 100k visible-items query 2.445 ms |

## Performance Gate

The `scripts/performance-gate.py` script:

- Discovers benchmarks in `frontend/vityo_app/benchmark/`
- Runs them via `dart run` when Dart VM is available
- Compares against baseline JSON when present
- Fails on regression greater than the configured threshold, defaulting to 10 percent
- Outputs machine-readable JSON

## Reproduce

```powershell
$env:PYTHONUTF8='1'
$env:PYTHONIOENCODING='utf-8'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$env:Path='T:\DevEnv\flutter\bin;T:\DevEnv\flutter\bin\cache\dart-sdk\bin;' + $env:Path
python scripts/performance-gate.py --json
```

To save a refreshed comparison baseline:

```powershell
python scripts/performance-gate.py --save-baseline
```

## Target Thresholds

| Metric | Target (p95) | Current p95 |
|--------|--------------|-------------|
| 10k-line file open | < 500 ms | 6.506 ms |
| 10k-line typing latency proxy | < 16 ms | 0.826 ms |
| 100k semantic span viewport query | < 5 ms | 0.985 ms |
| 100-package workspace graph build | < 2 s | 0.206 ms |
| Language cache hit latency | < 0.1 ms | 0.003 ms |
| 10k runtime events replay | < 1 s | 0.067 ms |
| AI context packing, 10k items | < 500 ms | 0.019 ms |
| 100-event watcher burst coalescing | < 50 ms | 0.010 ms |
| 10k-item virtualized list query | < 16 ms | 0.096 ms |
