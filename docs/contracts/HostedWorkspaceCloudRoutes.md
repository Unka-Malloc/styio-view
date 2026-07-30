# HostedWorkspaceCloudRoutes

**Purpose:** Record Vityo's `Platform hosted-workspace v1` consumer boundary.

**Last updated:** 2026-07-30

## Owner

Styio Platform is the sole owner of hosted workspace lifecycle, cloud jobs,
registry control, and workers. The published base path is
`/api/styio-hosted/v1`.

Vityo consumes route families for workspace open/refresh, dependency
sync/vendor, workflow execution, package deployment, document persistence, and
workspace lifecycle/export. Concrete route and envelope schemas are frozen by
the Platform OpenAPI contract.

## Excluded routes

The hosted contract has no compiler install, use, switch, or project-pin
operations. Styio is system-provided. Platform workers execute Pafio workflows
with an explicitly discovered Styio executable.

## Consumer invariants

1. Hosted state is consumed only through the Platform adapter.
2. Local project facts use `pafio metadata --json`.
3. Compiler and language-service facts use Styio machine contracts directly.
4. Vityo never infers hosted lifecycle state from filesystem layout.
5. Breaking hosted changes require a new Platform contract version.
