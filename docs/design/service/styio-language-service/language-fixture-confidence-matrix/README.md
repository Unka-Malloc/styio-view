# Language Fixture Confidence Matrix

**Purpose:** Define a standalone Vityo module for classifying external Styio language fixtures against declared expectations, using a confidence-matrix model to make valid, invalid, stale, and mislabeled samples auditable during StyioService migration.

**Last updated:** 2026-05-14

**Status:** Draft for review

## 1. Module Summary

The Language Fixture Confidence Matrix validates language sample files against explicit expectations.

It answers one question:

```text
Did the real Styio validation result match the expectation declared by the fixture?
```

The current Vityo implementation is a classifier and gate model, not a parser.
`LanguageFixtureConfidenceMatrixBuilder` receives fixture paths and pass/fail
results from a validator, classifies each row, and returns a metadata-only gate
summary. The validator may be the future embedded StyioService parser API,
Styio CLI syntax check, or a test double.

`LanguageFixtureFileCollector` scans fixture roots through `File System Manager`,
filters `.styio` files, and returns deterministic normalized paths. It does not
use `dart:io` directly, so the same gate shape can later run against local,
remote, browser, hosted, or virtual file-system providers.

`StyioServiceFixtureValidator` is the Vityo-side adapter from
`StyioServiceConnector` to matrix pass/fail results. It receives fixture text
from a caller-provided text loader, asks the connector to analyze the document,
and treats a successful response with no error diagnostics as pass. It does not
read files directly and does not implement Styio syntax.

`LanguageFixtureFileSystemTextLoader` reads fixture text through `File System
Manager` for local gate usage, and `LanguageFixtureGateRunner` composes the
collector, validator, and matrix builder into a single local gate surface.

`StyioServiceFixtureGate` is the connector-backed assembly point. It takes a
`File System Manager` and a `StyioServiceConnector`, then wires collection,
text loading, connector validation, and matrix classification together. When
the connector is `ToolchainStyioServiceConnector` or
`ToolchainManagerStyioServiceConnector`, the gate reaches the real configured
Styio toolchain path without adding another parser or process launcher inside
this module.

The gate also exposes factories for both toolchain paths:

| Factory | Use |
|---------|-----|
| `StyioServiceFixtureGate.fromToolchainRuntime` | Local command or one-shot runtime with a temporary catalog. |
| `StyioServiceFixtureGate.fromToolchainManager` | Product/runtime path that loads the selected language-service toolchain through Configuration-backed `ToolchainManager`. |

`tool/language_fixture_gate.dart` is the local command entry point for this
module. It registers the configured Styio executable as a temporary
language-service toolchain, runs fixtures through `ToolchainStyioServiceConnector`,
prints the matrix JSON, and fails on empty fixture sets or any strict gate
failure.
The command keeps stdout machine-readable as matrix JSON and prints a compact
human summary to stderr for CI logs.

`scripts/language-fixture-gate.sh` is the repository-level wrapper. It resolves
the Styio executable from `--styio-bin`, `STYIO`, sibling `styio-nightly` build
outputs, `/usr/local/bin/styio`, or `PATH`, then runs the Flutter tool command.
By default, the wrapper scans only the parser-backed CI fixture roots
`test/fixtures/language_service` and
`test/fixtures/styio_language/syntax_contract`. Use repeated `--fixture-root`
options when intentionally validating a broader fixture set.
`scripts/checkpoint-health.sh` calls this wrapper by default, and the GitHub
local CI workflow builds sibling `styio-nightly` before invoking the Vityo gate.

This module exists because Vityo currently has language samples from several sources:

1. real Styio examples,
2. expected-failure diagnostics cases,
3. legacy pseudo-syntax samples,
4. IDE fallback samples,
5. migration fixtures copied out of inline Dart tests.

Without explicit classification, Vityo cannot tell whether a failing sample is a real regression, an intentional negative test, or stale pseudo syntax.

## 2. Terminology

This module defines positive as:

```text
positive = the fixture is valid Styio and should pass the selected Styio validation contract
```

Negative means:

```text
negative = the fixture is invalid Styio and should fail the selected Styio validation contract
```

## 3. Confidence Matrix

| Fixture marker | Expectation | Actual result | Matrix class | Meaning |
|----------------|-------------|---------------|--------------|---------|
| `*.true.styio` | pass | pass | True Positive | A fixture declared as valid Styio was correctly accepted. |
| `*.true.styio` | pass | fail | False Negative | A fixture declared as valid Styio was rejected. The fixture may be stale, or StyioService may have regressed. |
| `*.false.styio` | fail | fail | True Negative | A fixture declared as invalid Styio was correctly rejected. |
| `*.false.styio` | fail | pass | False Positive | A fixture declared as invalid Styio was accepted. The expectation may be wrong or the validator may be too permissive. |
| unmarked `.styio` | missing | pass or fail | Unlabeled | The fixture has no declared expectation and must be classified before it can gate anything. |

## 4. Fixture Naming Contract

The file name is the first expectation source.

| Pattern | Declared expectation |
|---------|----------------------|
| `*.true.styio` | The fixture should pass. |
| `*.false.styio` | The fixture should fail. |
| Any other `.styio` file | Unlabeled unless a manifest overrides it. |

Recommended examples:

```text
valid-binding.true.styio
invalid-token.false.styio
legacy-function-syntax.false.styio
```

## 5. Manifest Override Contract

A future manifest may override or enrich file-name expectations.

Example:

```json
{
  "schemaVersion": 1,
  "contract": "language-fixture-confidence-matrix",
  "fixtures": [
    {
      "path": "fixtures/styio_language/valid-binding.true.styio",
      "expectation": "pass",
      "validationMode": "syntax"
    },
    {
      "path": "fixtures/styio_language/legacy-function-syntax.false.styio",
      "expectation": "fail",
      "validationMode": "syntax"
    }
  ]
}
```

Manifest support is optional at first. File-name expectations are sufficient for the initial module.

## 6. Validation Modes

| Mode | Source of truth | Use |
|------|-----------------|-----|
| syntax | StyioService syntax check or `styio check --syntax --json` | Parser compatibility and syntax migration. |
| semantic | StyioService semantic diagnostics | Type, symbol, import, and resource diagnostics. |
| adapter | Vityo language adapter output | Verifies Vityo consumes StyioService output correctly. |
| fallback | Vityo fallback validator | Verifies degraded mode only; must not be called Styio truth. |

The default first implementation should use `syntax` mode.

## 7. Module Inputs

| Input | Required | Notes |
|-------|----------|-------|
| Fixture root | Yes | Directory containing `.styio` files. |
| File System Manager | Yes | Scans fixture roots and reads fixture text without direct `dart:io` use in the Service module. |
| Styio validation command or service endpoint | Yes for syntax/semantic/adapter modes | The selected Styio truth source. |
| Expectation source | Yes | File names or manifest. |
| Validation mode | Yes | Starts with `syntax`. |
| Contract version | Recommended | Used to compare results across Styio grammar changes. |

## 8. Module Outputs

The module should produce a machine-readable summary.

Example:

```json
{
  "schemaVersion": 1,
  "contract": "language-fixture-confidence-matrix",
  "validationMode": "syntax",
  "summary": {
    "truePositive": 12,
    "trueNegative": 8,
    "falsePositive": 1,
    "falseNegative": 3,
    "unlabeled": 2
  },
  "items": [
    {
      "path": "fixtures/styio_language/valid-binding.true.styio",
      "expectation": "pass",
      "actual": "pass",
      "matrixClass": "truePositive"
    }
  ]
}
```

## 9. Gate Policy

`Gate Policy` is the single decision point for expectation parsing, actual-result normalization, matrix classification, and gate outcome.

| Fixture marker | Expectation | Actual result | Matrix class | Gate result | Meaning |
|----------------|-------------|---------------|--------------|-------------|---------|
| `*.true.styio` | pass | pass | True Positive | pass | A valid fixture was accepted by the selected Styio validation contract. |
| `*.true.styio` | pass | fail | False Negative | fail | A valid fixture was rejected. The fixture may be stale, or the Styio validation contract may have regressed. |
| `*.false.styio` | fail | fail | True Negative | pass | An invalid fixture was rejected by the selected Styio validation contract. |
| `*.false.styio` | fail | pass | False Positive | fail | An invalid fixture was accepted. The expectation may be wrong or the validator may be too permissive. |
| unmarked `.styio` | missing | pass or fail | Unlabeled | fail | The fixture has no declared expectation and must be classified before it can gate anything. |

The initial gate should be strict: any False Positive, False Negative, or Unlabeled item fails the gate.

## 10. Ownership Boundary

| Responsibility | Owner |
|----------------|-------|
| Fixture expectation model | Vityo |
| Fixture file organization | Vityo |
| Running the gate in Vityo tests | Vityo |
| Styio syntax truth | StyioService |
| Styio semantic truth | StyioService |
| Interpretation of false-positive parser acceptance | Joint review between Vityo and StyioService owners |
| Interpretation of false-negative parser rejection | Joint review between Vityo and StyioService owners |

## 11. Relationship To Runtime Dependencies

This module replaces the older `Styio Fixture Expectation Gate` name.

In the delivered Vityo design baseline, this appears as `Language Fixture Confidence Matrix`.

It is a Service Layer module because it evaluates language samples. It depends on the Toolchain or Execution path when the selected validation source is a CLI or service process.

## 12. Non-Goals

1. This module does not implement a Styio parser.
2. This module does not decide Styio syntax truth.
3. This module does not replace unit tests for the language adapter.
4. This module does not hide failing fixtures by relabeling them automatically.
5. This module does not use Vityo fallback syntax validation as the default source of truth.

## 13. First Implementation Sketch

Implemented local anchors:

1. `LanguageFixtureFileCollector` scans roots through `File System Manager`.
2. `LanguageFixtureFileSystemTextLoader` reads fixture text through `File System Manager`.
3. `StyioServiceFixtureValidator` maps `StyioServiceConnector` diagnostics to pass/fail.
4. `LanguageFixtureConfidenceMatrixBuilder` classifies `.true.styio`, `.false.styio`, and unlabeled fixtures.
5. `LanguageFixtureGateRunner` composes scanning, validation, and classification into one gate result.
6. `StyioServiceFixtureGate` wires File System Manager and StyioServiceConnector into a reusable connector-backed fixture gate.
7. `StyioServiceFixtureGate.fromToolchainRuntime` and `StyioServiceFixtureGate.fromToolchainManager` expose explicit one-shot and product-runtime toolchain entry points.
8. `tool/language_fixture_gate.dart` exposes the gate as a local Dart command backed by the Toolchain connector.
9. `scripts/language-fixture-gate.sh` and `scripts/checkpoint-health.sh` wire the command into the repository health gate.

Remaining external integration:

1. Confirm the GitHub-hosted CI run after the sibling `styio-nightly` build step executes on a remote runner.
