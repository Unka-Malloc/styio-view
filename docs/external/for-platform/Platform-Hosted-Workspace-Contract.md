# Platform Hosted Workspace Contract

**Purpose:** Freeze Vityo's consumer boundary for `Platform hosted-workspace v1`.

**Last updated:** 2026-07-30

## Ownership

Styio Platform owns the hosted workspace API, workspace lifecycle, cloud jobs,
registry control, and workers. Pafio remains the project workflow executable
used inside a worker; it does not host this API.

## Consumed route families

The published `/api/styio-hosted/v1` API provides:

1. workspace open and project metadata refresh;
2. dependency sync and vendor operations;
3. `check`, `build`, `run`, and `test` workflow execution;
4. pack, publish preflight, and publish operations;
5. hosted document load and save;
6. workspace close, retention, and export lifecycle.

There are no compiler install, use, switch, or project-pin routes. Hosted
workers invoke `pafio build` and point it at a system-provided Styio compiler.

## Consumer rules

1. Vityo uses the Platform adapter for hosted state only.
2. Local project facts continue to come from `pafio metadata --json`.
3. Language services consume Styio contracts directly.
4. Vityo does not infer hosted lifecycle state from local files or URLs.
