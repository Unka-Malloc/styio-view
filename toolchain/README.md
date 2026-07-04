# Toolchain Backend Surface

**Purpose:** Make `toolchain/` the repo-local home for backend-owned toolchain assets, handoff notes, and mockable examples used by `Vityo`.

**Last updated:** 2026-06-19

## What This Directory Owns

- stable profile tables consumed by repo bootstrap and verification scripts
- the current maintenance tool and skill inventory consumed by the release gate
- backend-side normalization notes for toolchain state, route selection, and management actions
- frontend handoff guidance for install/use/pin status and capability rendering
- non-authoritative example payloads that let frontend and backend work in parallel

## Directory Map

- `android-sdk-profiles.csv`
  Stable Android profile table. Keep this path stable because scripts, Dockerfiles, and build docs already consume it.
- `apple-platform-profiles.csv`
  Stable Apple profile table. Keep this path stable for the same reason.
- `maintenance-tools.json`
  Current-only inventory for release, health, docs, platform, prototype, language, and environment maintenance tools and skills. `scripts/release-readiness-gate.py` validates it before release.
- `backend/`
  Backend-owned notes about the toolchain lane that `Vityo` owns inside this repo.
- `handoff/`
  Frontend/backend interface notes for teams building UI against the toolchain backend surface.
- `examples/`
  Working example payloads for local mocks and early tests. These are not the product-contract source of truth.

## Ownership Rules

1. `toolchain/` is not a Flutter UI area and must not accumulate page copy, widget state, or screen-specific view models.
2. `styio-nightly` remains the compiler and managed-toolchain SSOT.
3. `styio-pafio` remains the backend-service and hosted-control-plane owner for project, dependency, and hosted workspace routes.
4. `Vityo` owns the product-facing backend adapter surface that consumes those upstream machine contracts and hands normalized state to the frontend.
5. Canonical adapter contracts still live under `docs/contracts/`; files here are a repo-local backend working area, not a replacement SSOT.

## Frontend Consumption Rule

Frontend teams should consume the backend surface through published adapter contracts and hosted route payloads. Direct reads of raw profile CSVs, `.pafio` internals, or compiler install layout are for bootstrap tooling only, not the main product runtime path.
