# Toolchain Backend Ownership

**Purpose:** Define the backend-owned surface that `Vityo` carries locally for toolchain management and status normalization.

**Last updated:** 2026-04-21

## Backend Responsibilities

The `Vityo` toolchain backend owns:

1. loading and selecting repo-local platform profiles
2. deciding whether a request should use `local-cli`, `ffi`, or `hosted` routing
3. normalizing toolchain state into a frontend-friendly snapshot
4. exposing install/use/pin/clear-pin actions through one result-envelope shape
5. returning structured `blocked` or `partial` states when upstream capability is missing

## Upstream Inputs

### From `styio-nightly`

- compiler version and channel truth
- managed compiler install/use/pin semantics
- machine-info and capability publication

### From `styio-pafio`

- project graph and toolchain state payloads
- dependency and registry state needed by environment/toolchain views
- hosted control-plane routes and envelopes for remote workspaces

## Non-Goals

1. no compiler implementation lives here
2. no package-manager service implementation lives here
3. no Flutter widget logic or visual state lives here
4. no repo-private filesystem heuristics should leak into the user-facing contract when a published machine payload exists

## Working Output Shape

Backend work in this directory should converge on a small, stable field family for frontend consumers:

- route kind
- selected and default profile names
- compiler version and channel
- install root and binary path when available
- capability flags for install/use/pin/clear-pin
- blocked reasons and recovery hints

The example payload under `../examples/` is the local mock shape for parallel work. If a field becomes product-contract truth, promote it to `docs/contracts/` or the relevant upstream SSOT instead of treating the example as normative.
