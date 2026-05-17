# Shell Runtime

**Purpose:** Document the `docs/design/environment/shell-runtime/` collection scope, ownership, and maintenance rules.
**Last updated:** 2026-05-17

Shell Runtime is an Environment module that coordinates shell-oriented execution through the Environment stack. It is not a UI shell and not an editor controller.

## 1. Environment Placement

Shell Runtime crosses the system-compatibility side and the application-side environment modules:

```text
Shell runtime call path:
  Toolchain / Shell Runtime                 # application-side environment caller
    -> Platform Manager / Shell Manager     # top system-compatibility call surface
      <- Platform Adapter / Shell Adapter
        <- Platform Context / Shell Facts
          <- Platform Detector / Shell Prober # detector preset plus concrete shell prober

Other application-side environment modules:
  Configuration
  Extension
```

The application-side environment modules have no strict global order. Configuration, Toolchain, and Extension may reference each other through explicit contracts, but none of them should become a universal parent layer.

## 2. Shell Runtime Chain

```text
Toolchain / Shell Runtime                 # application-side environment user
  -> Platform Manager / Shell Manager     # top system-compatibility call surface
    <- Platform Adapter / Shell Adapter
      <- Platform Context / Shell Facts
        <- Platform Detector
          <- OS / Runtime shell APIs
```

Runtime execution calls the top manager surface. Facts are produced bottom-up by detectors, normalized into facts contracts, adapted into manager context, and consumed at the manager boundary. Detector, Facts, and Adapter never call Shell Runtime.

## 3. Shell-Specific Responsibilities

| Environment part | Shell-specific responsibility |
|---|---|
| Platform Detector / Shell Prober | Platform Detector defines Prober behavior; Shell Prober implements it for raw shell-related signals such as available shells, shell executable paths, process host, executable lookup behavior, PTY support, shell version hints, and OS shell defaults. |
| Platform Context / Shell Facts | Carry normalized facts such as shell family, path separator expectations, quoting family hint, login-shell support, PTY capability, and script extension hints. |
| Platform Adapter / Shell Adapter | Convert Shell Facts into Shell Manager context for quoting, invocation shape, env handoff, cwd handling, and capability fallback. |
| Platform Manager / Shell Manager | Expose stable shell operations: build command invocation, quote arguments, select shell profile, prepare cwd/env/stdin/stdout, and return structured failures. |
| Configuration / Shell Configuration | Own user/workspace shell preferences, environment overlays, default profiles, workspace shell policy, and degraded-mode preferences required by Shell Runtime. |
| Toolchain / Shell Runtime | Own toolchain-bound shell execution profiles for Styio, Spio, build/run/test, and task commands. |
| Extension | Contribute optional shell profiles, tasks, command providers, or runtime integrations through explicit manifests and permissions. |


## 3.1 Shell Prober Boundary

`Shell Prober` is a concrete Prober under the Platform Detector global interface preset.

| Shell Prober does | Shell Prober must not do |
|---|---|
| Probe available system shells. | Choose the active shell profile. |
| Detect shell executable paths and version hints. | Quote arguments or build command lines. |
| Detect shell family hints such as `posix`, `powershell`, `cmd`, or `unknown`. | Execute user commands. |
| Detect login-shell support, PTY support, and script extension hints. | Apply user/workspace configuration. |
| Report raw or partially normalized facts to Shell Facts. | Decide fallback or recovery UI. |

Flow:

```text
Shell Prober
  -> Shell Facts
  -> Shell Adapter
  -> Shell Manager
  <- Toolchain / Shell Runtime
```

## 4. Non-Responsibilities

| Capability | Owner |
|---|---|
| App shell UI, terminal panel UI, recovery UI | Appearance |
| Command routing and user intent | Interaction |
| Styio language facts | Service / Styio Language Service |
| Raw OS probing | Platform Detector |
| Normalized host/toolchain/workspace facts | Platform Context |
| Generic process spawning | Platform Manager / Process Manager or Execution Manager |
| Tool discovery and selected Styio/Spio versions | Toolchain |
| Extension activation and contribution lifecycle | Extension |

## 5. Shell Runtime Rules

| Rule | Meaning |
|---|---|
| Shell Runtime consumes facts, not raw OS APIs | It must not probe shells directly when Platform Detector/Facts can provide the fact. |
| Shell Runtime uses Shell Manager for shell behavior | Quoting, command shape, cwd/env handoff, PTY support, and structured shell failures belong behind Shell Manager. |
| Shell Runtime is toolchain-aware | Build/run/test shell routes are bound to selected toolchain profiles, Shell Configuration, Shell Facts, and project configuration. |
| Shell Runtime is not a global terminal UI | It may power terminal/task execution, but rendering and terminal surfaces belong to Appearance. |
| Extension contributions are optional | Extensions may contribute shell profiles or tasks, but Shell Runtime must keep core local execution independent of extensions. |

## 6. Structured Failure Shape

Shell Runtime should receive structured failures from Shell Manager and Execution Manager instead of raw process errors.

| Field | Meaning |
|---|---|
| `kind` | `shellUnavailable`, `unsupportedShell`, `permissionDenied`, `cwdUnavailable`, `envRejected`, `ptyUnsupported`, `processFailed`, or another stable failure kind. |
| `operation` | The shell operation being attempted, such as quote, spawn, run script, or open PTY. |
| `target` | Shell profile, executable, script, cwd, or task identity. |
| `sourceManager` | `ShellManager`, `ExecutionManager`, or another operation-owning manager. |
| `recoveryHint` | User-visible recovery guidance for Appearance/App Shell surfaces. |

## 7. Configuration Dependency

Shell Runtime consumes Shell Configuration, but Shell Configuration does not execute shell behavior.

```text
Shell Configuration
  + EnvironmentVariableResolver
  + Shell Facts
  + Toolchain selection
  + Workspace target
  -> Shell Runtime
  -> Shell Manager request
```

Detailed shell configuration design: [../configuration-store/shell-configuration/README.md](../configuration-store/shell-configuration/README.md)

Terminal launch environment should use the same Configuration-owned environment
overlay contract as Toolchain launch. `TerminalRuntime` builds PTY session
environment through `EnvironmentVariableResolver`, combining inherited
environment, parsed env-file variables, shell configuration overlays,
workspace/profile overlays, selected shell profile environment, and runtime
overrides before calling `PtyManager.start`.

## 8. Implementation Target

```text
frontend/vityo_app/lib/src/view_ide/environment/shell_runtime/
  shell_runtime.dart
  shell_profile.dart
  shell_command_plan.dart
  shell_failure.dart
```

Existing shell runtime code may remain at compatibility paths while migrating, but new shell runtime behavior should follow this Environment boundary.

## Relationship With Shell Prober

`Shell Prober` is the shell-specific implementation of the global `Platform Detector` prober contract. It only detects available shell capabilities and publishes shell facts.

`Shell Runtime` must combine `Shell Configuration`, `Shell Facts`, toolchain selection, and workspace target information before asking `Shell Manager` to perform execution-related work.

## Relationship With Platform Context

`Shell Runtime` should read shell capability through `Platform Context` snapshots, not by probing the host directly. The shell-specific section remains `Shell Facts`, while the global container is `Platform Context`.

```text
Shell Prober
  -> Shell Facts
    -> Platform Context
      -> Platform Adapter / Shell Adapter
        -> Platform Manager / Shell Manager
          -> Toolchain / Shell Runtime
```
