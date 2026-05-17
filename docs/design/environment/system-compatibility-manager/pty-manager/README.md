# PTY Manager

**Purpose:** Document the `docs/design/environment/system-compatibility-manager/pty-manager/` collection scope, ownership, and maintenance rules.
**Last updated:** 2026-05-17

`PTY Manager` is the Platform Manager component for pseudo-terminal capability. It owns OS-facing terminal device behavior that `Shell Manager` and `Process Manager` should not absorb.

A PTY is not a shell. A shell is a command interpreter such as `bash`, `zsh`, `sh`, or `powershell`. A PTY is the operating-system terminal device abstraction that lets an interactive process believe it is attached to a real terminal.

## 1. Position

```text
Toolchain / Terminal Runtime
  -> Platform Manager / PTY Manager
    <- Platform Adapter / PTY Adapter
      <- Platform Context / PTY Facts
        <- Platform Detector / PTY Prober
```

The lower system boundary is:

```text
OS PTY APIs
  -> Platform Detector / PTY Prober
    -> Platform Context / PTY Facts
      -> Platform Adapter / PTY Adapter
        -> Platform Manager / PTY Manager
```

## 2. Why PTY Manager Is Separate From Shell Manager

| Concern | Shell Manager | PTY Manager |
|---|---|---|
| Main domain | Shell command semantics. | OS terminal device semantics. |
| Example target | `bash -c "cmd"`, quoting, login shell flags. | `openpty`, `forkpty`, ConPTY, terminal resize. |
| Lifecycle | Usually one command to one result. | Long-running interactive session. |
| I/O model | Final stdout/stderr result or command output stream. | Continuous terminal byte stream. |
| Resize | Not relevant for non-interactive command execution. | Core capability: rows/cols changes. |
| Control input | Shell command string and arguments. | Raw stdin, Ctrl+C, Ctrl+D, terminal control bytes. |
| Applies only to shell? | Yes, shell-specific. | No. `vim`, `top`, `less`, `python`, `ssh`, `gdb` can all run in a PTY. |

Design rule:

```text
Shell Manager may use PTY Manager for interactive shell sessions.
PTY Manager must not be owned by Shell Manager.
```

## 3. Responsibilities

| Responsibility | Meaning |
|---|---|
| PTY allocation | Create or request a pseudo-terminal session when the host supports it. |
| Session handle | Return a stable handle for stdin, output stream, resize, and close operations. |
| Interactive process attachment | Attach a process or shell executable to the PTY slave side. |
| Resize | Apply terminal rows/cols changes to the PTY. |
| Input forwarding | Write raw terminal input to the PTY. |
| Output streaming | Expose terminal output as a stream without UI interpretation. |
| Capability downgrade | Report unsupported or degraded PTY capability without crashing upper layers. |
| OS-specific compatibility | Hide Linux/macOS PTY and Windows ConPTY differences behind one contract. |

## 4. Non-Responsibilities

| Not Owned By PTY Manager | Owner |
|---|---|
| Shell profile selection | `Configuration / Shell Configuration` and `Toolchain / Terminal Runtime`. |
| Shell quoting and `-c` command composition | `Platform Manager / Shell Manager`. |
| Ordinary non-interactive process execution | `Platform Manager / Process Manager`. |
| Terminal panel UI | Appearance layer. |
| Terminal text rendering, cursor, font, theme | Appearance layer. |
| User keybinding and paste handling | Interaction layer. |
| Scrollback buffer policy | Interaction or Toolchain runtime, depending on final terminal model. |
| Language service daemon protocol | Service layer. |

## 5. Four-Layer Foundation

```text
Platform Manager / PTY Manager
  <- Platform Adapter / PTY Adapter
    <- Platform Context / PTY Facts
      <- Platform Detector / PTY Prober
```

| Layer | Module | Responsibility |
|---|---|---|
| Platform Detector | `PTY Prober` | Detect whether PTY-like capability exists on the current host or target. |
| Platform Context | `PTY Facts` | Store normalized PTY capability facts. |
| Platform Adapter | `PTY Adapter` | Convert PTY facts into manager-ready compatibility behavior. |
| Platform Manager | `PTY Manager` | Expose PTY session operations to upper layers. |

## 6. PTY Facts

`PTY Facts` should be a section inside `Platform Context`, not a separate global singleton.

Suggested fields:

```text
PtyFacts
  targetId
  operatingSystem
  distributionId
  architecture
  providerKind
  supportsPty
  supportsResize
  supportsRawMode
  supportsSignals
  supportsProcessGroup
  supportsConPty
  supportsForkPty
  detectedAt
```

Suggested fact keys:

| Fact Key | Meaning |
|---|---|
| `pty.providerKind` | `posix-pty`, `conpty`, `hosted`, `unsupported`, or `unknown`. |
| `pty.supported` | Whether PTY sessions are available. |
| `pty.resizeSupported` | Whether rows/cols resize can be applied. |
| `pty.rawModeSupported` | Whether raw terminal input mode can be used. |
| `pty.signalsSupported` | Whether control signals such as Ctrl+C can be forwarded. |
| `pty.processGroupSupported` | Whether process-group terminal semantics are available. |
| `pty.forkPtySupported` | Whether POSIX-style `forkpty` is available. |
| `pty.conPtySupported` | Whether Windows ConPTY is available. |

## 7. PTY Prober

`PTY Prober` follows the global `Platform Detector` prober contract. It only detects raw capability and emits facts.

It may inspect:

| Probe | Example |
|---|---|
| OS family | Linux, macOS, Windows, web, hosted. |
| Runtime mode | desktop, automation, hosted, web. |
| POSIX PTY hints | `/dev/ptmx`, `/dev/pts`, libc/native extension availability. |
| Windows PTY hints | ConPTY availability. |
| Permission signals | Whether the runtime is allowed to allocate a terminal device. |

It must not allocate a long-running terminal session as part of normal probing. If a capability requires an active allocation test, that probe should be explicitly budgeted and side-effect-safe.

## 8. PTY Adapter

`PTY Adapter` converts facts into compatibility decisions.

Examples:

| Fact Input | Adapter Output |
|---|---|
| Linux + PTY supported | Use POSIX PTY implementation. |
| Windows + ConPTY supported | Use ConPTY implementation. |
| Hosted runtime | Use hosted terminal bridge if registered. |
| Web runtime without host bridge | Mark PTY unsupported and let Terminal Runtime degrade. |
| Resize unsupported | Allow session start but reject resize operations with structured result. |

The adapter must not render terminal output and must not choose shell profile.

## 9. PTY Manager API Shape

A future implementation should expose a small session-oriented API:

```text
PtyManager
  facts
  compatibility
  start(request) -> PtySession

PtySession
  id
  state
  outputStream
  write(input)
  resize(rows, cols)
  close()
```

Suggested request shape:

```text
PtySessionRequest
  executablePath
  arguments
  workingDirectory
  environment
  rows
  cols
```

Suggested result/state model:

```text
PtySessionState
  starting
  running
  exited
  closed
  failed
  unsupported
```

## 10. Relationship With Terminal Runtime

`Terminal Runtime` belongs above Platform Manager. It is a product/runtime composition layer, not the OS abstraction itself.

```text
Toolchain / Terminal Runtime
  -> Shell Configuration
  -> Shell Manager
  -> Process Manager
  -> PTY Manager
```

`Terminal Runtime` should decide:

| Decision | Owner |
|---|---|
| Which shell profile to launch | Terminal Runtime + Shell Configuration. |
| Whether to start an interactive terminal | Terminal Runtime. |
| Whether to fall back to non-interactive command execution | Terminal Runtime. |
| How to bind the session to UI | Interaction + Appearance. |

`PTY Manager` only provides the OS-level interactive terminal session capability.

## 11. Failure Envelope

Current implementation exposes `PtyOperationFailure` through manager-local `failureForSession(...)` and `failureForResize(...)`.

| Failure kind | Meaning |
|---|---|
| `unsupported` | PTY sessions are not available for the current platform/provider. |
| `startFailed` | The PTY backend failed to start or initialize a session. |
| `resizeUnsupported` | The session can run, but resize is not supported by the backend. |
| `resizeFailed` | Resize was attempted and failed. |
| `sessionFailed` | A running session entered a failed state. |
| `unknownFailure` | The failure cannot be classified safely. |

This failure envelope belongs to PTY Manager. Shell Manager should not classify PTY allocation or resize failures.

## 11. Relationship With Process Manager

`Process Manager` owns ordinary process execution. `PTY Manager` owns terminal-attached process execution.

```text
Process Manager
  -> process run/start without terminal device

PTY Manager
  -> process attached to pseudo-terminal device
```

A future implementation may share lower native process helpers, but the public contracts should stay separate.

## 12. First Compatibility Target

For the current Linux Debian ARM host, the first target should be:

```text
linux-debian-arm
```

Expected initial capability decision:

| Capability | Expected Linux Debian ARM Target |
|---|---|
| POSIX PTY | Supported if native PTY bridge is available. |
| Resize | Supported through PTY ioctl/native bridge. |
| Raw input | Supported through PTY/native terminal mode. |
| ConPTY | Not applicable. |
| Hosted terminal bridge | Not required for local desktop target. |

Important implementation note: Dart `dart:io` does not expose full PTY allocation by itself. A real `PTY Manager` implementation will need a native bridge, plugin, FFI layer, or hosted terminal bridge. Until that exists, `PTY Facts` should report PTY as unavailable or partial rather than pretending `Process.run` is a PTY.

## 13. Design Rule

If the feature is about shell language, command quoting, or shell profile, keep it in `Shell Manager` or `Shell Configuration`.

If the feature is about OS terminal devices, interactive process attachment, terminal resize, raw input, or PTY lifecycle, put it in `PTY Manager`.
