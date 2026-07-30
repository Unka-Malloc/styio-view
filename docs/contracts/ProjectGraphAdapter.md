# ProjectGraphAdapter

**Purpose:** Define how Vityo assembles its project view without taking
ownership from Pafio, Styio, or Styio Platform.

**Last updated:** 2026-07-30

## Source split

| Vityo concern | Authoritative source |
|---|---|
| local package, workspace, dependency, target, lock, resolution, vendor facts | `pafio metadata --json` (`metadata v1`) |
| compiler identity and supported contracts | `styio --machine-info=json` |
| hosted workspace lifecycle and cloud execution | `Platform hosted-workspace v1` |

The adapter converts these owner contracts into Vityo view models. It does not
publish a competing graph protocol.

## Local behavior

1. `VITYO_PAFIO_BIN`, when non-empty, selects the Pafio executable; otherwise
   Vityo uses `pafio` from `PATH`.
2. A local `pafio.toml` identifies project mode but is not parsed for package
   facts.
3. Invalid or unavailable `metadata v1` produces a stable blocked snapshot.
4. Scratch mode remains available only when no project manifest exists.
5. The adapter never reads Pafio's private home or cache layout.

## Compiler behavior

1. `VITYO_STYIO_BIN`, when non-empty, selects Styio; otherwise Vityo uses
   `styio` from `PATH`.
2. Vityo invokes `styio --machine-info=json` directly.
3. Vityo does not ask Pafio to install, select, pin, cache, or describe Styio.

## Hosted behavior

Hosted routes are handled by the Platform adapter. Hosted state is not folded
into Pafio metadata and cannot be reconstructed from local project files.
