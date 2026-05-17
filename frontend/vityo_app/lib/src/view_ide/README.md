# View IDE Boundary

`view_ide` is the functional IDE boundary.

This layer owns IDE state machines, contracts, and capability services. It may
model editor state, project/workspace state, language intelligence, execution
routes, toolchain adapters, runtime events, module lifecycle, and agent profile
state.

Rules:

1. Prefer pure Dart.
2. Do not import Flutter widget or Material presentation APIs here.
3. Do not decide visual layout, spacing, colors, or responsive composition.
4. Expose typed state, commands, diagnostics, events, and blocked reasons for
   `view_render` to present.
5. Keep upstream compiler, package-manager, hosted-control-plane, and registry
   behavior behind adapter contracts.

Current status:

`language/` is the first-class IDE intelligence area and owns local parsing,
syntax highlighting, symbol indexing, diagnostics, completion, hover, and
refactoring preflight helpers.

Language is split into five submodules:

1. `contract/`: public language data contracts.
2. `syntax/`: tokenization, syntax highlighting, semantic token/block ranges.
3. `semantic/`: symbol indexing, references, definitions, and usage metadata.
4. `service/`: language-service interfaces and fallback orchestration.
5. `features/`: completion, hover, quick-fix, intention, rename, and refactor
   helpers as they are extracted from the fallback service.

`backend_toolchain/` owns the toolchain, execution, hosted-control-plane,
dependency, deployment, and capability adapter layer.

`editor/` owns document state, selection state, render-plan metadata, and the
editor controller. Widget painting and input presentation remain outside this
layer. Editor internals are split into:

1. `document/`: document text, revision, line/offset conversion, and range replacement.
2. `selection/`: caret and selection ranges.
3. `controller/`: editing session orchestration, language-service coupling, undo/redo stacks, and notifications.
4. `render_plan/`: render-layer metadata consumed by presentation surfaces.
5. `transactions/`: reserved boundary for extracted mutation transactions and undo/redo semantics.
6. `actions/`: reserved boundary for completion, formatting, quick-fix, navigation, and refactor actions.

`workspace/` owns workspace/project selection state and document persistence
stores.

`module_host/` owns module manifests, capability matrices, lifecycle policy, and
registry loading.

`runtime/` owns runtime replay, lane, graph, and debug-lane summaries as pure
state. Render colors are mapped by `view_render`.

`shell_runtime/` owns the IDE shell runtime model: command execution, blocked
reasons, debug log, active execution session, runtime-event capture, project
graph refresh, document persistence, dependency source commands, deployment
commands, and toolchain commands. It must not own bottom tabs, scaffold layout,
or Flutter shortcuts.

`agent/` owns agent/provider profile state.

`commands/` owns IDE command descriptors and pure shortcut specifications.
Flutter `Intent` and shortcut activator binding remain in the render adapter.

`platform/` owns platform target detection and wire labels. Viewport-responsive
layout belongs to `view_render/platform`.

The legacy `../language/`, `../backend_toolchain/`, `../editor/`,
`../module_host/`, `../agent/`, `../runtime/`, `../platform/`, and selected
`../app/state/` directories must remain compatibility facades for existing
imports while new functional code lands under `view_ide`. Render shell legacy
paths under `../app/state/shell_*` and `../app/layout/vityo_shell_scaffold.dart`
must point to `view_render/shell`, not back into this layer.

Move additional implementation files here only when the dependency direction
remains:

```text
view_render -> view_ide
view_ide    -> no view_render
```
