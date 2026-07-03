# Frontend Handoff

**Purpose:** Fix the working handoff between frontend teams and the repo-local toolchain backend surface.

**Last updated:** 2026-04-21

## Frontend Entry Points

Frontend code should bind to:

1. `ToolchainManagementAdapter`
2. `ProjectGraphAdapter`
3. `DependencySourceAdapter` when environment state needs dependency-source context
4. `AdapterCapabilitySnapshot`
5. hosted toolchain routes published by `styio-pafio` for remote workspaces

## What Frontend May Use From `toolchain/`

1. `examples/*.example.json` for local mocks, fixtures, or early state-shape tests
2. the profile CSV files for bootstrap and developer tooling only
3. backend notes in `backend/` when implementing UI against an unfinished route

## What Frontend Must Not Do

1. parse `.pafio`, compiler install symlinks, or cache layout to infer live toolchain state
2. read raw profile CSVs on the main runtime path instead of consuming normalized backend state
3. guess hosted-workspace availability from URL shape or repo layout
4. turn missing upstream capability into silent fallback behavior

## Backend Commitments To Frontend

1. return structured `blocked` and `partial` states instead of ambiguous failures
2. keep route selection explicit
3. surface selected profile, compiler version, and channel in one normalized payload family
4. expose management actions as backend operations, not UI-authored filesystem mutations

If these commitments need new fields or behaviors, update `docs/contracts/` or the relevant `docs/for-pafio/` handoff, then sync the example payloads here.
