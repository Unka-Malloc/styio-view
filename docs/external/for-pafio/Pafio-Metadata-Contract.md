# Pafio Metadata Contract

**Purpose:** Freeze the only local project-description contract consumed by Vityo.

**Last updated:** 2026-07-30

## Entry point

Vityo invokes:

```text
pafio metadata --json
```

The payload is `metadata v1`. Its top-level object contains exactly:

1. `package`
2. `workspace`
3. `dependencies`
4. `targets`
5. `lock`
6. `resolution`
7. `vendor`

`package` and `workspace.packages` describe package identity and workspace
membership. `dependencies` describes resolved dependency edges and their
sources. `targets` describes buildable targets. The remaining objects expose
lock, resolution, and vendor state.

## Consumer rules

1. Vityo does not parse `pafio.toml`, `pafio.lock`, or Pafio's private storage
   to reconstruct package facts.
2. Missing or invalid metadata blocks the local project adapter; it does not
   trigger an inferred project graph.
3. Compiler identity and capability are not metadata fields. Vityo obtains
   them directly from `styio --machine-info=json`.
4. Hosted workspace state is not metadata. Vityo obtains it from Styio
   Platform's `hosted-workspace v1` API.
5. Cloud policy, managed compiler state, and IDE aggregation fields are not
   accepted in `metadata v1`.
