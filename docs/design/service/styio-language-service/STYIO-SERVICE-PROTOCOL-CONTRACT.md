# StyioService Protocol Contract

**Purpose:** Record the StyioService Protocol Contract reference material for Vityo architecture, release, or maintenance work.

**Last updated:** 2026-05-17

This document defines the Vityo-side contract for consuming StyioService language facts. It is written for future StyioService CLI, daemon, LSP, or embedded API implementations.

The contract is intentionally language-owned: Vityo consumes facts, renders UI, applies edits, and manages workflow state, but it must not invent Styio compiler truth.

## 1. Transport Boundary

Vityo currently supports a JSONL protocol through `StyioCliJsonlProtocol`.

Current CLI invocation shape:

```text
styio --parser-engine nightly --error-format jsonl --file <file>
```

Optional context:

```text
--config <config-path>
--file <file-path>
```

The current real CLI is only observed as a reliable syntax diagnostics source. The protocol below defines the structured facts Vityo can already consume once StyioService emits them.

## 2. Record Kinds

Each JSONL line must be one JSON object. The record kind is read from the first available field:

```text
kind
type
record
```

Supported record kinds:

| Record kind | Meaning |
|---|---|
| `diagnostic` / `error` | Syntax or semantic diagnostic. |
| `completion` / `completionItem` | One completion item. |
| `hover` | One hover payload. |
| `semantic` / `semanticToken` / `semanticSpan` | One semantic span. |
| `formatting` / `formattingEdit` / `formatEdit` | One formatting edit. |
| `semanticBlock` / `block` | One block range for folding/structure. |
| `inlayHint` / `inlay` | One inlay hint. |
| `symbol` / `documentSymbol` | One document symbol. |
| `reference` / `referenceSpan` | One reference span. |
| `codeAction` / `quickFix` / `intention` | One code action fact. |
| `rename` / `renamePlan` | One rename plan. |
| `safeDelete` / `safeDeletePlan` | One safe-delete plan. |
| `inlineVariable` / `inlineVariablePlan` | One inline-variable refactor plan. |
| `introduceVariable` / `introduceVariablePlan` | One introduce-variable refactor plan. |
| `extractFunction` / `extractFunctionPlan` | One extract-function refactor plan. |
| `changeSignature` / `changeSignaturePlan` | One change-signature refactor plan. |
| `parameterInfo` / `signatureHelp` | One parameter-info payload. |
| `facts` / `semanticFacts` / `semanticSnapshot` / `languageSnapshot` | A batch envelope containing multiple language fact arrays. |
| `capability` / `capabilityState` / `capabilityStatus` | One explicit capability state declaration. |

Unknown record kinds are currently interpreted as diagnostics for backwards compatibility. New StyioService producers should not rely on unknown kinds.

## 3. Facts Envelope

Preferred future output is a published facts envelope. This lets StyioService emit a coherent snapshot in one JSONL record.

Example:

```json
{
  "record": "facts",
  "protocolVersion": "styio-service-facts-v1",
  "facts": {
    "diagnostics": [
      {
        "severity": "warning",
        "code": "styio.demo",
        "message": "demo",
        "range": { "start": 0, "end": 5 }
      }
    ],
    "completions": [
      {
        "label": "value",
        "kind": "variable",
        "insertText": "value"
      }
    ],
    "hovers": [
      {
        "markdown": "**value**",
        "range": { "start": 0, "end": 5 }
      }
    ],
    "semanticSpans": [
      {
        "kind": "variable",
        "range": { "start": 0, "end": 5 }
      }
    ],
    "documentSymbols": [
      {
        "name": "value",
        "kind": "variable",
        "nameRange": { "start": 0, "end": 5 },
        "declarationRange": { "start": 0, "end": 5 }
      }
    ],
    "references": [
      {
        "name": "value",
        "kind": "variable",
        "range": { "start": 0, "end": 5 },
        "targetRange": { "start": 0, "end": 5 },
        "isDeclaration": true
      }
    ],
    "capabilities": [
      {
        "capability": "completion",
        "state": "available"
      },
      {
        "capability": "hover",
        "state": "unsupported",
        "message": "hover facts are not emitted by this toolchain"
      }
    ]
  }
}
```

## 4. Capability States

StyioService should explicitly report capability states when possible. This avoids forcing Vityo to infer support from missing payloads.

Supported states:

| State | Meaning |
|---|---|
| `available` | The capability is supported and has a fresh authoritative result. |
| `derived` | The result can be derived from other authoritative semantic facts. Prefer emitting the underlying facts instead of this state when possible. |
| `empty` | The capability is supported, the request succeeded, and the result is intentionally empty. |
| `unsupported` | The toolchain/service does not support this capability. |
| `unavailable` | The capability might exist, but the service or environment is unavailable. |
| `failed` | The capability failed for this request. |
| `protocol-error` | The capability result could not be decoded according to the protocol. |
| `stale` | The result is not for the current document revision. |

Capability identifiers use Vityo wire values:

```text
diagnostics
completion
hover
semantic-tokens
formatting
semantic-blocks
inlay-hints
document-symbols
references
definition
code-actions
rename
safe-delete
inline-variable
introduce-variable
extract-function
change-signature
parameter-info
```

## 5. Range Contract

Ranges are offset ranges in the document text provided to StyioService.

Accepted range shape:

```json
{ "start": 0, "end": 5 }
```

Aliases accepted by Vityo:

```text
offset -> start
startOffset -> start
endOffset -> end
length -> end = start + length
```

Vityo clamps `end` to `start` if the decoded end is smaller than start.

## 6. Ownership Boundary

| Fact | Owner |
|---|---|
| Syntax diagnostics | StyioService |
| Semantic diagnostics | StyioService |
| Type facts | StyioService |
| Scope graph / symbols | StyioService |
| References / definition | StyioService |
| Completion candidates | StyioService |
| Hover raw content | StyioService |
| Semantic token classification | StyioService |
| Rename/refactor safety | StyioService |
| Code action raw edits | StyioService |
| UI popup rendering | Vityo |
| Status panels | Vityo |
| Workspace edit application | Vityo |
| Fallback display when unsupported | Vityo |
| Local fallback behavior | Vityo, but not compiler truth |

## 7. Compatibility Policy

Vityo accepts both:

1. Individual JSONL records for streaming or simple CLI output.
2. `record: facts` envelopes for coherent snapshot output.

The facts envelope is preferred for future StyioService implementations because completion, hover, diagnostics, semantic tokens, references, and code actions often need to be coherent for the same document revision and project context.

If StyioService cannot provide a capability, it should emit an explicit `unsupported` state instead of omitting the capability silently.

## 8. Current Implementation Evidence

Vityo-side protocol support is covered by:

```text
flutter test test/styio_service_connector_test.dart --name "JSONL protocol|capability detector"

+8 All tests passed
```

The executable facts-envelope fixture is:

```text
frontend/vityo_app/test/fixtures/styio_service/facts_envelope.jsonl
```

Status surface compatibility is covered by:

```text
flutter test test/language_service_status_surface_test.dart test/editor_language_service_status_widget_test.dart

+6 All tests passed
```
