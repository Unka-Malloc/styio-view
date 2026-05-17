# Editor Vertical Flow View

**Purpose:** Document the `docs/design/architecture-views/vertical-flow-diagrams/editor/` collection scope, ownership, and maintenance rules.
**Last updated:** 2026-05-17

`Editor` is not a runtime layer and must not become a vertical implementation directory. It is a design view that crosses Appearance, Interaction, Service, and Environment.

Concrete editor implementation must stay horizontally split. The vertical view exists only to review whether UI, rendering, editing behavior, service facts, file IO, configuration, and runtime state are crossing layer boundaries correctly.

## 1. Layer Stack

```text
Appearance Layer
  -> App Shell Surface / Editor Surface
  -> Editor Renderer / Decoration Renderer / Hover Renderer / Completion Renderer
Interaction Layer
  -> Command Router
  -> Editor Controller
  -> Edit Transaction
  -> Document Model / Text Buffer / Selection Model / Undo Redo Model
  -> Document Resource Binding / Marker Model / Decoration Model
Service Layer
  -> Styio Language Service
  -> User Service, only when optional account/profile state is displayed
Environment Layer
  -> DataStore API / Configuration Store
  -> File System Manager / Toolchain Manager / Execution Manager
  -> System Specific File System Manager
OS / External
  -> OS File System / OS Process API / Toolchain Download Endpoint
```

## 2. Ownership Table

| Layer | Editor component | Responsibility |
|---|---|---|
| Appearance | Editor Surface | Expose visible editor entry points, open/save intent, recent file entry, settings entry, recovery guidance, and capability status. |
| Appearance | Editor Renderer | Render text, line numbers, gutter, cursor, selection, minimap, and base editor visual state. |
| Appearance | Decoration / Hover / Completion Renderers | Render markers, decorations, hover widgets, completion popups, semantic highlight styles, and other visual overlays. |
| Interaction | Command Router | Route commands to the correct interaction owner without owning command behavior. |
| Interaction | Editor Controller | Coordinate editing behavior and editor state owners. It must not become the owner of every editor submodel. |
| Interaction | Edit Transaction | Group edits, selection updates, undo grouping, dirty-state changes, and service invalidation into one coherent operation. |
| Interaction | Document Model | Own document identity, URI, provider id, language id, revision, dirty state, and binding state. |
| Interaction | Text Buffer | Own current in-memory text content and text mutation primitives. |
| Interaction | Selection Model | Own cursor, selection, multi-cursor, and selection history. |
| Interaction | Undo Redo Model | Own edit history, undo grouping, redo grouping, and command integration. |
| Interaction | Document Resource Binding | Bind an editor document to a File System Manager resource and coordinate open, save, reload, conflict, and external-change behavior. |
| Interaction | Marker Model | Hold diagnostics, warnings, errors, and service-origin markers independently of renderer details. |
| Interaction | Decoration Model | Hold visual decoration intent independently of renderer details. |
| Service | Styio Language Service | Provide diagnostics, completion, hover, semantic tokens, definition, references, rename facts, code actions, and language snapshots. |
| Service | User Service | Optional. Provides account/profile/session status only when editor surfaces need to display it. Local editing must not depend on login. |
| Environment | DataStore API | Persist IDE-owned state through environment-owned storage primitives. It is not a Service Layer API. |
| Environment | Configuration Store | Provide editor, language, theme, file, and keybinding configuration. |
| Environment | File System Manager | Own file-system behavior: provider routing, URI/path handling, read/write/watch, file content codec, and structured errors. |
| Environment | Toolchain Manager | Own selected Styio toolchain, service launch context, version binding, and capability handshake support. |
| Environment | Execution Manager | Own process/task execution semantics where editor commands need execution. |

## 3. Required Internal Separation

The editor must not collapse into a single `Editor Controller` object.

```text
Editor Controller
  -> Edit Transaction
  -> Document Model
  -> Text Buffer
  -> Selection Model
  -> Undo Redo Model
  -> Document Resource Binding
  -> Marker Model
  -> Decoration Model
```

Rules:

| Rule | Meaning |
|---|---|
| Controller coordinates | It routes behavior and coordinates state owners. |
| Models own state | Document, buffer, selection, undo/redo, marker, and decoration models own their own mutation rules. |
| Transactions group edits | Edit Transaction is the boundary for coherent text edits, state updates, undo grouping, service invalidation, and dirty-state changes. |
| Rendering consumes models | Renderers consume model output; renderers do not own editor state. |

## 4. File Binding Boundary

`Document Resource Binding` belongs to Interaction because it understands editor document state.

`File System Manager` belongs to Environment because it owns file-system behavior.

```text
Editor Controller
  -> Document Resource Binding
    -> File System Manager
      -> System Specific File System Manager
        -> OS / File System
```

This path is for user/project files.

IDE-owned editor state uses DataStore:

```text
Editor Controller
  -> Editor DataStore Owner
    -> Foundation / DataStore API
      -> File System Manager
        -> System Specific File System Manager
          -> OS / File System
```

Rules:

| Rule | Meaning |
|---|---|
| Document Resource Binding is editor-aware | It owns binding state such as unbound, bound clean, dirty, external changed, deleted, conflicted, read-only, and provider unavailable. |
| File System Manager is provider-aware | It owns read/write/watch, provider routing, path/URI handling, file content codec, and structured file errors. |
| DataStore API is Foundation | DataStore is shared application mechanics and must not be shown as Environment or Service. |
| File content codec is FS-owned | Project-file content decoding/encoding belongs to File System Manager, not Toolchain Encoder/Decoder. |

## 5. Document Resource Binding States

| State | Meaning |
|---|---|
| `unbound` | The editor has content without a backing resource, such as an untitled file. |
| `binding` | A file load or resource binding is in progress. |
| `boundClean` | The buffer matches the last known saved file version. |
| `boundDirty` | The buffer has unsaved edits. |
| `externalChanged` | The backing file changed outside the editor. |
| `deletedOnDisk` | The backing file was deleted or became unavailable. |
| `conflicted` | Save cannot proceed safely without user choice. |
| `readonly` | The backing resource exists but cannot be written. |
| `providerUnavailable` | The file-system provider or remote workspace is unavailable. |

## 6. Marker And Decoration Boundary

Language and runtime facts must not render directly to UI.

```text
Styio Language Service
  -> language facts
  -> Marker Model / Decoration Model
  -> Appearance renderers
  -> Editor Surface / UI
```

| Model | Inputs | Consumers |
|---|---|---|
| Marker Model | Diagnostics, warnings, errors, stale-service states, structured runtime failures. | Diagnostics renderer, gutter, problems surface, recovery UI. |
| Decoration Model | Semantic tokens, search matches, selection decorations, inline hints, code-lens-like visual intents, diff markers. | Editor renderer, theme rendering, hover renderer, completion renderer. |

This keeps Service output separate from visual rendering decisions.

## 7. Service Boundary

Editor flows consume `Styio Language Service`, not its internal modules.

Allowed upper-layer dependency:

```text
Interaction
  -> Styio Language Service
```

Disallowed upper-layer dependencies:

```text
Interaction -> Styio Result Adapter
Interaction -> Styio Service Connector
Appearance  -> Styio Result Adapter
Appearance  -> Styio Service Connector
```

Internal service structure:

```text
Styio Language Service
  -> Styio Service Connector
  -> Styio Result Adapter
  -> Language Result Cache
  -> Language Fixture Confidence Matrix
```

## 8. Async, Cancellation, And Stale Result Rules

Editor responsiveness is a hard boundary.

| Rule | Meaning |
|---|---|
| Typing never waits for StyioService | Text edits must update the buffer immediately and invalidate service results asynchronously. |
| Rendering never waits for file IO | UI may show pending or stale state, but paint should not block on storage. |
| Save may wait, but must expose pending state | Save is allowed to wait for File System Manager, but the editor must show pending/conflict/failure state. |
| Language results are cancellable or stale-rejected | Diagnostics, completion, hover, semantic tokens, and references must bind to document version and service capability. |
| File watch events are coalesced | External file changes should be coalesced/debounced before reaching editor behavior. |
| Workspace analysis is background-only | Large language or project analysis must not run in the UI/editing critical path. |

## 9. Open File Flow

```text
Editor Surface / UI
  -> Command Router
  -> Editor Controller
  -> Document Resource Binding
  -> File System Manager.read
  -> Text Buffer
  -> Document Model
  -> Editor Renderer
  -> Editor Surface / UI
```

## 10. Save File Flow

```text
Editor UI / Save Intent
  -> Editor Surface
  -> Command Router
  -> Editor Controller
  -> Edit Transaction
  -> Document Resource Binding
  -> File System Manager.write
  -> structured result
  -> Document Model saved revision update
  -> Editor DataStore Owner dirty/tab state update
  -> Marker Model / Recovery State update when needed
  -> Editor Renderer
  -> Editor UI
```

Save must not call OS file APIs directly.

Save must not write editor DataStore records by hand.

## 11. External Change Flow

```text
File System Manager watch event
  -> Document Resource Binding
  -> coalesce/debounce
  -> Editor Controller conflict policy
  -> Document Model binding state update
  -> Marker Model recovery marker when needed
  -> Editor Renderer shows reload/compare/recover action
  -> Styio Language Service invalidates stale snapshots when needed
```

The editor decides product behavior after the file event, but the file event source remains File System Manager.

## 12. Layered Review Diagram

```text
Appearance    | [ Editor Surface / UI ]  [ Recovery UI ]  [ Capability UI ]
            |   v
Appearance    | [ Editor Renderer ]  [ Decoration Renderer ]  [ Hover / Completion Renderer ]
            |   v
Interaction   | [ Command Router ]
            |   v
Interaction   | [ Editor Controller ]
            |   |  [ Edit Transaction ]  [ Document Model ]  [ Text Buffer ]  [ Selection Model ]  [ Undo Redo Model ]
            |   |  [ Document Resource Binding ]  [ Marker Model ]  [ Decoration Model ]
            |   |             |                         |                  |
            |   |             v                         v                  v
Service       |   |      [ Styio Language Service ]   [ User Service ]   [ Service Capability Status ]
            |   |             |                         |
            |   v             v                         v
Environment   | [ DataStore API ]   [ Configuration Store ]   [ File System Manager ]   [ Toolchain Manager ]
            |   |                                              |                       |
            |   v                                              v                       v
Environment   | [ System Specific Storage ]                    [ System Specific FS Manager ] [ Selected Styio Toolchain ]
            |   |                                              |                       |
            |   v                                              v                       v
OS            | [ OS / File System ]                          [ OS File System ]       [ OS Process API ]
External(Web)| [ Toolchain Download Endpoint ]
```

## 13. What Must Not Happen

| Anti-pattern | Reason |
|---|---|
| Editor calls OS file APIs directly. | Bypasses provider routing, remote/browser support, structured errors, local permission checks, and watchers. |
| File System Manager reads Editor DataStore state. | Reverses the dependency direction. |
| DataStore API is placed in Service Layer or Environment. | DataStore is Foundation shared mechanics, not a user-facing service or platform manager. |
| Document Resource Binding is treated as pure Environment. | It owns editor binding state and conflict policy, so it belongs to Interaction. |
| Editor File Binding persists layout, cursor, tabs, or undo metadata directly to files. | IDE state belongs to DataStore. |
| Service Layer reads files behind the editor. | Language facts must bind to editor document versions or explicit workspace snapshots. |
| Editor or Appearance depends on Styio Result Adapter directly. | Adapter is internal to Styio Language Service. |
| Toolchain Encoder/Decoder handles editor project-file content. | Toolchain codecs are for process/protocol IO; file content codec belongs to File System Manager. |
| Registry drives every editor flow step. | Registry registers boundaries only; editor internals stay local to horizontal owners. |

## 14. StyioService Toolchain Placement

`StyioService` is not part of `OS/External` in the editor vertical flow.

It is launched from a selected Styio toolchain managed by the Environment layer.

```text
Appearance    | [ Toolchain Selection UI ]  [ Install / Select / Recovery UI ]
            |   v
Interaction   | [ Toolchain Command Flow ]  [ Retry / Switch / Pin Flow ]
            |   v
Service       | [ Styio Language Service ]
            |   |  [ Styio Service Connector ]  [ Capability Detector ]
            |   v
Environment   | [ Toolchain Manager ]
            |   |  [ Styio Toolchain Discovery ]  [ Managed Installer ]  [ Version Selector ]
            |   v
Environment   | [ Selected Styio Toolchain ]
            |   |  [ styio ]  [ styio_lspd ]  [ syntax CLI ]  [ future embedded endpoint ]
            |   v
Environment   | [ Execution Manager ]  [ Toolchain Environment Builder ]  [ Toolchain Encoder / Decoder ]
            |   v
OS            | [ OS Process API ]  [ OS File System ]
External(Web)| [ Toolchain Download Endpoint ]
```

Editor recovery should offer product choices when the selected toolchain is unavailable:

| Failure | Recovery choices |
|---|---|
| No Styio toolchain selected | Select existing toolchain, install managed toolchain, use degraded mode. |
| Selected toolchain missing | Locate again, install replacement, clear selection, use degraded mode. |
| Version incompatible | Switch version, upgrade/downgrade managed version, show required contract. |
| StyioService failed to start | Retry, show logs, switch transport, use CLI fallback, use degraded mode. |
| Capability missing | Disable unsupported feature, show capability gap, request upstream contract. |

Detailed toolchain design: [../../../environment/toolchain-manager/styio-toolchain-management/README.md](../../../environment/toolchain-manager/styio-toolchain-management/README.md)
