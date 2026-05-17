# Repository Hygiene

**Purpose:** Define the repository hygiene entrypoint for `Vityo` so contributors and CI use one script to reject generated artifacts, dependency payloads, and undocumented binary blobs.

**Last updated:** 2026-04-19

## Command

Tracked-tree hygiene:

```bash
python3 scripts/repo-hygiene-gate.py --mode tracked
```

Staged-only hygiene:

```bash
python3 scripts/repo-hygiene-gate.py --mode staged
```

Push-range hygiene:

```bash
python3 scripts/repo-hygiene-gate.py --mode push --range origin/main..HEAD
```

## Scope

This gate rejects:

1. generated and dependency directories such as `build/`, `.dart_tool/`, `node_modules/`, and `.artifacts/`
2. forbidden binary/archive suffixes in tracked files or pushed history
3. undocumented binary files outside the narrow allowlist
4. `.gitignore` drift against the shared cross-repo baseline
5. missing documentation references for the hygiene and delivery entrypoints, including `scripts/delivery-gate.sh`
6. `view_ide` / `view_render` boundary drift, including `view_ide` importing `view_render` or Flutter presentation APIs
7. legacy `src/backend_toolchain/*.dart` files carrying implementation instead of one-line facades to `src/view_ide/backend_toolchain/`
8. legacy `src/language/*.dart` files carrying implementation instead of one-line facades to `src/view_ide/language/`
9. top-level `src/view_ide/language/*.dart` files carrying implementation instead of facades/barrels over `contract/`, `syntax/`, `semantic/`, `service/`, and `features/`
10. top-level `src/view_ide/editor/*.dart` files carrying implementation instead of facades/barrels over `document/`, `selection/`, `controller/`, `transactions/`, `render_plan/`, and `actions/`
11. migrated functional files under legacy `src/editor/`, `src/app/state/`, `src/module_host/`, `src/agent/`, `src/runtime/`, and `src/platform/` carrying implementation instead of facades to `src/view_ide/`
12. migrated render surface files under legacy `src/agent/`, `src/editor/`, `src/runtime/`, `src/theme/`, and `src/platform/viewport_profile.dart` carrying implementation instead of facades to `src/view_render/`
13. command definitions drifting back into Flutter-specific command adapters instead of staying in `src/view_ide/commands/`
14. shell UI implementation drifting back into legacy `src/app/state/shell_*` or `src/app/layout/vityo_shell_scaffold.dart` instead of `src/view_render/shell/`
15. render bottom-tab state leaking into `src/view_ide/shell_runtime/`
