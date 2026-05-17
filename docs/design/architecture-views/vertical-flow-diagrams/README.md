# Vertical Flow Architecture Views

**Purpose:** Provide left-aligned character diagrams for Vityo vertical flows so horizontal same-layer components and cross-layer dependencies can be reviewed quickly without creating vertical implementation directories.

**Last updated:** 2026-05-16

**Status:** Draft for review

## 1. Diagram Rule

All diagrams are drawn from product/user surface at the top to OS, external service, or storage foundation at the bottom.

Use a left-aligned visual grammar everywhere:

```text
[ UI component A ]
  |  [ UI component B ]  [ UI component C ]
  v
[ Lower component ]
  |  [ Same lower layer B ]  [ Same lower layer C ]
  v
[ OS / External / Storage foundation ]
```

Rules:

| Rule | Meaning |
|---|---|
| Left edge | Primary vertical path starts at the left edge. |
| Same row | Additional boxes on the same row are horizontal peers at the same functional level. |
| Lower row | Lower dependency layer. |
| Bottom row | OS, external service, remote endpoint, browser storage, or persisted storage foundation. |
| Branches | Coordinated side paths, not necessarily parent-child runtime calls. |

These diagrams are review diagrams, not mandatory runtime call stacks and not runtime module directories.

## 2. Editor Line

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
Foundation    | [ DataStore API ]   [ Registry ]              [ Workspace Scope ]       [ Resource Coordinator ]
            |   |                         |                         |                       |
            |   v                         v                         v                       v
Environment   | [ File System Manager ]   [ Configuration Store ]   [ File System Manager ] [ Toolchain Manager ]
            |   |                                              |                       |
            |   v                                              v                       v
Environment   | [ System Specific Storage ]                    [ System Specific FS Manager ] [ Selected Styio Toolchain ]
            |   |                                              |                       |
            |   v                                              v                       v
OS            | [ OS / File System ]                          [ OS File System ]       [ OS Process API ]
External(Web)| [ Toolchain Download Endpoint ]
```

Review notes:

| Concern | Rule |
|---|---|
| Controller size | `Editor Controller` coordinates state owners; it must not become a God Object. |
| DataStore direction | `Editor DataStore Owner -> DataStore API -> File System Manager`, never `File System Manager -> DataStore API`. |
| DataStore layer | `DataStore API` is Foundation, not Environment or Service. |
| File binding | `Document Resource Binding` is Interaction; `File System Manager` is Environment. |
| Service boundary | Upper layers consume `Styio Language Service`, not `Styio Result Adapter` or `Styio Service Connector` directly. |
| Marker/decorations | Service facts flow into Marker/Decoration models before renderers. |
| Responsiveness | Typing and rendering must not wait for StyioService or file IO; results are cancellable or stale-rejected. |
| Styio placement | `StyioService` is launched from a selected Styio toolchain managed by Environment/Toolchain, not treated as OS. |

Detailed design: [editor/README.md](./editor/README.md)

## 3. Service Line

```text
Appearance    | [ Problems UI ]
            |   |  [ Completion Popup ]  [ Hover / Rename UI ]
            |   v
Appearance    | [ Diagnostic View ]
            |   |  [ Completion View ]  [ Hover / Rename View ]
            |   v
Interaction   | [ Editor Controller / Feature Flows ]
            |   |  [ Workspace Edit Applier ]  [ Service Commands ]
            |   v
Service       | [ Vityo Service Result Consumer ]
            |   |  [ Diagnostic Intake ]  [ Completion Intake ]  [ Hover/Semantic Intake ]  [ CodeAction/Rename Intake ]
            |   v
Service       | [ Styio Result Adapter ]
            |   |  [ Result Cache ]  [ Version Binding ]  [ Stale Rejection ]  [ DTO Normalizer ]
            |   v
Service       | [ Styio Service Connector ]
            |   |  [ Protocol ]  [ Transport ]  [ Client ]  [ Capability Detector ]
            |   v
Environment   | [ StyioService Process / CLI Runner ]
            |   |  [ Selected Styio Toolchain ]  [ Toolchain Manager ]  [ Capability Handshake ]
            |   v
Styio         | [ Styio Compiler / Language Truth ]
            |   |  [ Parser ]  [ Analyzer ]  [ Language Facts ]
            |   v
OS            | [ OS Process API ]  [ OS File System ]
External(Web)| [ Toolchain Download Endpoint ]
```

Review notes:

| Concern | Rule |
|---|---|
| Language truth | StyioService owns syntax and semantic truth. |
| Vityo role | Vityo adapts, caches, binds, renders, and applies product behavior. |
| Fallback | Fallback syntax validation is degraded product behavior, not Styio truth. |

## 4. DataStore Line

```text
Any Layer     | [ Layer Feature ]
            |   |  [ UI Subscriber ]  [ Runtime Subscriber ]
            |   v
Any Layer     | [ Layer DataStore Owner ]
            |   |  [ Mutation Authority ]  [ Observation Policy ]
            |   v
Foundation    | [ DataStore API ]
            |   |  [ Schema Version ]  [ Scope Policy ]  [ Migration Policy ]  [ Privacy / Sync Policy ]
            |   v
Environment   | [ File System Manager ]
            |   |  [ Cache Placement ]  [ Persistence Backend ]
            |   v
Environment   | [ System Specific File System Manager ]
            |   |  [ Local ]  [ Remote ]  [ Browser ]  [ Virtual ]  [ Hosted ]
            |   v
OS            | [ OS / File System ]
            |   |  [ Browser Storage ]  [ Remote Storage ]
```

Review notes:

| Concern | Rule |
|---|---|
| Ownership | Each stateful layer has a local DataStore Owner. |
| No reverse dependency | File System Manager must not depend on DataStore. |
| No global business hub | DataStore stores state; it does not execute feature behavior. |

Detailed design: [../../../foundation/data-store-owner/README.md](../../../foundation/data-store-owner/README.md)

## 5. Registry Line

```text
Any Layer     | [ Feature Owner ]
            |   |  [ Extension Contribution ]  [ App Shell Surface ]
            |   v
Any Layer     | [ Local Layer Registry ]
            |   |  [ Local Executable Lookup ]  [ Boundary Metadata ]
            |   v
Cross-Layer   | [ Registration Categories ]
            |   |  [ Schema ]  [ Provider ]  [ Command ]  [ Capability ]  [ Renderer ]  [ Policy ]
            |   v
Cross-Layer   | [ Registry Contract Writer ]
            |   |  [ Contract Version ]  [ Dependency Metadata ]  [ Ownership Metadata ]
            |   v
Cross-Layer   | [ External Manifest Index ]
            |   |  [ Discovery Metadata ]
```

Review notes:

| Concern | Rule |
|---|---|
| Boundary only | Registry records discoverable boundaries, not every helper or flow step. |
| Execution locality | Layer internals organize their own execution. |
| State separation | Registry metadata is not DataStore state. |

## 6. Configuration Line

```text
Appearance    | [ Settings UI ]
            |   |  [ Workspace Preference UI ]  [ Recovery / Preview UI ]
            |   v
Any Layer     | [ Configuration Consumer ]
            |   |  [ Theme Consumer ]  [ Keybinding Consumer ]
            |   v
Environment   | [ Configuration Store ]
            |   |  [ Settings Schema ]  [ Env Var Configuration ]  [ Theme Configuration ]  [ Cache / Endpoint Policy ]
            |   v
Environment   | [ Configuration DataStore Owner ]
            |   |  [ Profile Overrides ]  [ Workspace Overrides ]
            |   v
Cross-Layer   | [ DataStore API ]
            |   |  [ Secret Reference Store ]
            |   v
Environment   | [ File System Manager ]
            |   |  [ Secret Provider ]
            |   v
OS            | [ OS / File System ]
```

Review notes:

| Concern | Rule |
|---|---|
| User-configurable truth | Configuration owns user-configurable decisions. |
| Environment variables | Vityo stores IDE env overlays and merges them at launch time; it does not silently mutate OS-level environment variables. |
| Schema | Configuration must be schema-owned and migration-aware. |

Detailed design: [../../environment/configuration-store/environment-variable-configuration/README.md](../../environment/configuration-store/environment-variable-configuration/README.md)

## 7. Theme Line

```text
Appearance    | [ Theme Selection UI ]
            |   |  [ Theme Editor UI ]  [ Preview UI ]
            |   v
Appearance    | [ Appearance Renderer ]
            |   |  [ Editor Renderer ]  [ Panel / Widget Renderer ]
            |   v
Environment   | [ Theme Configuration ]
            |   |  [ Theme Tokens ]  [ Semantic Color Map ]  [ Icon Theme ]  [ Typography Map ]
            |   v
Environment   | [ Theme Package Registry ]
            |   |  [ Extension Theme Provider ]  [ Renderer Binding ]
            |   v
Environment   | [ Configuration DataStore ]
            |   |  [ Theme Package Store ]
            |   v
Environment   | [ File System Manager ]
```

Review notes:

| Concern | Rule |
|---|---|
| Language skipped | Theme may consume semantic token categories but must not change language analysis. |
| Rendering ownership | Appearance owns visual mapping and rendering. |
| Configuration | User-selected theme state is configuration/DataStore-backed, not language state. |

## 8. Execution Line

```text
Appearance    | [ Run / Test / Build UI ]
            |   |  [ Terminal UI ]  [ Artifact / Status UI ]
            |   v
Interaction   | [ Command Dispatcher ]
            |   |  [ Task Flow ]  [ Recovery Flow ]
            |   v
Environment   | [ Execution Manager ]
            |   |  [ Execution Profile Manager ]  [ Toolchain Environment Builder ]  [ Command Runner ]  [ Package Manager ]
            |   v
Environment   | [ Process Manager ]
            |   |  [ Toolchain Encoder ]  [ Toolchain Decoder ]
            |   v
Environment   | [ Process API Manager ]
            |   |  [ Shell Manager ]  [ Network Manager ]
            |   v
OS            | [ OS / Process ]
            |   |  [ OS / Shell ]
External     | [ External Toolchain ]
```

Review notes:

| Concern | Rule |
|---|---|
| Execution semantics | Execution Manager owns command execution semantics. |
| Process lifecycle | Process Manager owns process lifecycle. |
| IO conversion | Toolchain Encoder/Decoder own process/protocol IO conversion. |

## 9. Extension Line

```text
Appearance    | [ Extension UI ]
            |   |  [ Settings / Status UI ]  [ Recovery UI ]
            |   v
Any Layer     | [ Contribution Surface ]
            |   |  [ Appearance Contribution ]  [ Command Contribution ]  [ Language Contribution ]  [ Workflow Contribution ]
            |   v
Environment   | [ Extension Manager ]
            |   |  [ Lifecycle Manager ]  [ Provider Registry ]  [ Capability Registry ]  [ Permission Model ]
            |   v
Environment   | [ Plugin Manifest Loader ]
            |   |  [ Activation Policy ]  [ Contribution Metadata ]
            |   v
Environment   | [ Configuration Store ]
            |   |  [ Extension DataStore ]  [ Fallback Registry ]
            |   v
Environment   | [ File System Manager ]
            |   |  [ Network Manager ]  [ Process Manager ]
            |   v
OS            | [ OS / File System ]
            |   |  [ OS / Process ]
External(Web)| [ Network Endpoint ]
```

Review notes:

| Concern | Rule |
|---|---|
| No bypass | Extensions do not bypass registry, permission, capability, or configuration gates. |
| Contribution-specific | An extension may target only a subset of layers. |
| Provider boundaries | Provider contribution is replaceable boundary metadata plus local layer execution. |

## 10. System Compatibility Line

```text
Appearance    | [ Recovery / Consent UI ]
            |   |  [ Disabled State UI ]  [ Capability Status UI ]
            |   v
Any Layer     | [ Feature Owner ]
            |   |  [ Action Gating ]  [ Structured Failure UI ]
            |   v
Environment   | [ Platform Manager Interface ]
            |   |  [ File System Manager ]  [ Process / Shell Manager ]  [ Network Manager ]  [ Manager-local Permission Checks ]  [ Resource Manager ]
            |   v
Environment   | [ Platform Adapter ]
            |   |  [ File System Adapter ]  [ Process Adapter ]  [ Network Adapter ]
            |   v
Environment   | [ Platform Context ]
            |   |  [ Host Facts ]  [ Workspace Facts ]  [ Toolchain Facts ]
            |   v
Environment   | [ Platform Detector ]
            |   |  [ System Probers ]  [ File System Prober ]
            |   v
OS            | [ OS / Runtime / Host ]
            |   |  [ File System ]  [ Process APIs ]  [ Network APIs ]
```

Review notes:

| Concern | Rule |
|---|---|
| Facts only | Platform Context records facts; it does not execute behavior. |
| Interface vs implementation | Platform Manager is the interface term; System Specific Manager is the concrete implementation. |
| Feature ownership | Feature owners use manager APIs and structured failures instead of direct OS calls. |

Detailed designs:

| Module | Document |
|---|---|
| Platform Context | [../../environment/system-compatibility-manager/platform-context/README.md](../../environment/system-compatibility-manager/platform-context/README.md) |
| File System Manager | [../../environment/system-compatibility-manager/file-system-manager/README.md](../../environment/system-compatibility-manager/file-system-manager/README.md) |
| System Compatibility Manager | [../../environment/system-compatibility-manager/README.md](../../environment/system-compatibility-manager/README.md) |

## 11. File System Manager Line

```text
Any Layer     | [ Upper Functionalities ]
            |   |  [ Editor File Binding ]  [ DataStore / Configuration Store ]
            |   v
Environment   | [ File System Manager API ]
            |   |  [ Provider Router ]  [ Path Resolver ]  [ Watch Service ]  [ Error Classifier ]
            |   v
Environment   | [ System Specific File System Manager ]
            |   |  [ Local FS Manager ]  [ Remote / Browser FS Manager ]  [ Virtual FS Manager ]  [ Hosted FS Manager ]
            |   v
Environment   | [ Platform Adapter ]
            |   |  [ File System Facts Adapter ]  [ Provider Context ]
            |   v
Environment   | [ Platform Context ]
            |   |  [ File System Facts ]  [ Workspace Target Facts ]
            |   v
Environment   | [ Platform Detector / File System Prober ]
            |   |  [ Host Detector ]
            |   v
OS            | [ OS / File System ]
            |   |  [ Browser Storage ]
External(Web)| [ Remote / Hosted Storage ]
```

Review notes:

| Concern | Rule |
|---|---|
| File behavior | Upper layers must not bypass File System Manager for file-system behavior. |
| DataStore | DataStore may use File System Manager as a backend; File System Manager must not depend on DataStore. |
| Codec boundary | File content codec handles persisted files; Toolchain Encoder/Decoder handle process/protocol IO. |

Detailed design: [../../environment/system-compatibility-manager/file-system-manager/README.md](../../environment/system-compatibility-manager/file-system-manager/README.md)

## 12. Directory Tree

```text
docs/design/
  architecture-views/
    README.md
    vertical-flow-diagrams/
      README.md
      editor/
        README.md

  appearance/
    README.md
    app-shell-surface/
      README.md

  interaction/
    README.md

  service/
    README.md
    styio-language-service/
      README.md
      styio-result-adapter/
        README.md
      language-fixture-confidence-matrix/
        README.md
    user-service/
      README.md

  environment/
    README.md
    data-store-owner/
      README.md
    configuration-store/
      environment-variable-configuration/
        README.md
    system-compatibility-manager/
      README.md
      platform-context/
        README.md
      file-system-manager/
        README.md
    toolchain-manager/
      styio-toolchain-management/
        README.md
```
