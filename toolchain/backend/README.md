# Toolchain Backend Ownership

**Purpose:** Define the backend-owned surface that `Vityo` carries locally for compiler discovery and status normalization.

**Last updated:** 2026-04-21

## Backend Responsibilities

The `Vityo` toolchain backend owns:

1. loading and selecting repo-local platform profiles
2. deciding whether a request should use `local-cli`, `ffi`, or `hosted` routing
3. normalizing system Styio machine facts into a frontend-friendly snapshot
4. returning structured `blocked` or `partial` states when upstream capability is missing

## Upstream Inputs

### From `styio-nightly`

- compiler identity and capability truth through `styio --machine-info=json`
- diagnostics, receipt, and runtime-event contracts

### From Pafio

- local package, workspace, dependency, target, lock, resolution, and vendor facts through `pafio metadata --json`
- local workflow JSON for `check/build/run/test`

### From Styio Platform

- hosted workspace and cloud execution routes

## Non-Goals

1. no compiler implementation lives here
2. no package-manager service implementation lives here
3. no Flutter widget logic or visual state lives here
4. no Pafio private filesystem or environment reads
5. no Styio install, update, pin, switch, or cache ownership

## Working Output Shape

Backend work in this directory should converge on a small, stable field family for frontend consumers:

- route kind
- selected and default profile names
- system compiler identity and advertised capabilities
- Pafio metadata and workflow availability
- Platform hosted-workspace availability
- blocked reasons and recovery hints

The example payload under `../examples/` is the local mock shape for parallel work. If a field becomes product-contract truth, promote it to `docs/contracts/` or the relevant upstream SSOT instead of treating the example as normative.
