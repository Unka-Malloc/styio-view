# Appearance

**Purpose:** Document the `docs/design/appearance/` collection scope, ownership, and maintenance rules.
**Last updated:** 2026-05-17

Appearance owns visible presentation: app shell surfaces, rendering, theme mapping, visual widgets, icons, decorations, semantic highlighting, and responsive presentation.

Only boundary or complex appearance modules get their own README. Ordinary renderer submodules are recorded here until they need a dedicated design document.

## Module Inventory

| Module | Responsibility | Separate doc |
|---|---|---|
| `app-shell-surface/` | Top-level visible shell, onboarding, recovery, capability status, and account entry surfaces. | Yes |
| `renderer` | Shared rendering primitives and renderer boundaries. | No |
| `theme-rendering` | Theme token mapping to visual styles. | No |
| `editor-renderer` | Editor text, gutter, cursor, selection, minimap, and base visual editor states. | No |
| `diagnostics-renderer` | Diagnostic markers, problem visuals, and severity presentation. | No |
| `language-service-status-renderer` | Renders Interaction-owned language service status surfaces, including runtime state, capability freshness, and recovery status, without interpreting StyioService payloads. | No |
| `file-binding-status-renderer` | Renders Interaction-owned file binding status, external-change conflicts, and recovery actions without owning file-system behavior. | No |
| `toolchain-status-renderer` | Renders Interaction-owned toolchain status and recovery actions without executing installers, selecting tools, or mutating configuration. | No |
| `hover-renderer` | Hover widget rendering. | No |
| `completion-renderer` | Completion popup rendering. | No |
| `semantic-highlight-renderer` | Maps semantic token and decoration intent into visible editor styles. | No |

## Boundary

Appearance consumes Interaction state and Service facts after they have been converted into UI-facing models. It must not own editor command behavior, language truth, file-system behavior, toolchain behavior, configuration persistence, or account/session logic.

Language service status follows this boundary:

```text
Service / StyioServiceRuntimeStatusSnapshot
  -> Interaction / LanguageServiceStatusSurface
    -> Appearance / language-service-status-renderer
      -> Editor Surface / status card and status pills
```

Appearance may render severity, title, message, capability state labels, and
recovery affordances supplied by Interaction. It must not inspect raw
StyioService responses, decide capability freshness, retry the toolchain, or
mutate language-service sessions.

The visible form may vary by viewport. Mobile panes should prefer compact status
pills to avoid displacing editor actions, while desktop panes may render the full
status card for active, refreshing, degraded, or failed service states.

File binding status follows the same boundary:

```text
Interaction / DocumentResourceBindingSnapshot
  -> Appearance / file-binding-status-renderer
    -> Editor Surface / recovery banner
```

Appearance may render external-change, conflict, readonly, deleted, and provider
unavailable states. It may invoke an Interaction/Shell callback such as
`acceptEditorExternalChange`, but it must not read files, resolve conflicts, or
decide language cache invalidation itself.

Toolchain status rendering follows this boundary:

```text
Interaction / ToolchainStatusSurface
  -> Appearance / toolchain-status-renderer
    -> Runtime Surface / status card
    -> Settings Surface / toolchain settings status card
```

Appearance may render the selected source, version, channel, last command, and
recovery action labels. It must not execute a toolchain command, inspect raw
Toolchain payloads, install tools, or decide which Styio version is valid.

Toolchain recovery buttons call an Interaction/Shell callback. Appearance owns
only the button rendering and disabled/enabled presentation; Shell owns the
route intent or command retry.

Settings may reuse the same `ToolchainStatusSurface` projection. This keeps
Toolchain settings visible outside the Runtime tab without making the Settings
surface a second Toolchain Manager.

Settings may additionally render `ToolchainSettingsSurface` details such as
registered toolchain candidates, normalized capability states, durable recovery
state, and install history. These are display-only projections unless the user
invokes an Interaction/Shell command.

Candidate selection affordances may be rendered by Appearance, but the action
must cross back into Interaction/Shell. Appearance must not mutate toolchain
catalog state or Configuration records.

The same rule applies to clearing active candidates. Appearance may show the
affordance, but Shell and Toolchain own the action and persisted state change.
