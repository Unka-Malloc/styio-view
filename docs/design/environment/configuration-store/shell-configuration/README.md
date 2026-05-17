# Shell Configuration

**Purpose:** Document the `docs/design/environment/configuration-store/shell-configuration/` collection scope, ownership, and maintenance rules.
**Last updated:** 2026-05-17

Shell Configuration belongs to Environment / Configuration.

It stores the configuration required by Shell Runtime. It does not probe available shells, build command lines, quote arguments, or execute commands.

## 1. Position

```text
Configuration / Shell Configuration
  -> Toolchain / Shell Runtime
    -> Platform Manager / Shell Manager
      <- Platform Adapter / Shell Adapter
        <- Platform Context / Shell Facts
          <- Platform Detector / Shell Prober
```

`Shell Configuration` is application-owned persisted configuration. `Shell Facts` are detected system facts. They must not be merged into the same module.

## 2. Responsibilities

| Configuration area | Meaning |
|---|---|
| Default shell profile | User or workspace preference for which shell profile Shell Runtime should request. |
| Shell profile overrides | Optional profile name, executable path override, args, login-shell flag, and env overlay references. |
| Workspace shell policy | Workspace-specific allowed shell profile, cwd behavior, and task shell preference. |
| Environment overlays | References to IDE-owned env overlays used by shell execution. Actual OS env mutation is not allowed. |
| Terminal/task defaults | Defaults for shell-backed terminal/task routes, such as working directory policy and PTY preference. |
| Degraded-mode preferences | User/workspace choice for fallback behavior when preferred shell is unavailable. |

## 3. Non-Responsibilities

| Capability | Owner |
|---|---|
| Detect available shells | Platform Detector / Shell Prober |
| Store detected shell facts | Platform Context / Shell Facts |
| Convert shell facts into execution context | Platform Adapter / Shell Adapter |
| Quote arguments or build invocation shape | Platform Manager / Shell Manager |
| Execute shell commands | Shell Manager / Execution Manager |
| Select Styio/Spio toolchain version | Toolchain Manager |
| Render terminal, recovery, or settings UI | Appearance / App Shell Surface |

## 4. Stored Shape

Logical configuration shape:

```json
{
  "schemaVersion": 1,
  "defaultProfileId": "workspace-default",
  "profiles": [
    {
      "id": "workspace-default",
      "displayName": "Workspace Default",
      "shellFamilyPreference": "posix",
      "executablePathOverride": null,
      "args": [],
      "loginShell": false,
      "ptyPreferred": true,
      "envOverlayIds": ["workspace-shell"]
    }
  ],
  "workspacePolicy": {
    "cwdMode": "workspaceRoot",
    "allowExecutableOverride": true,
    "fallbackMode": "ask"
  }
}
```

## 5. Resolution Rule

Shell Runtime resolves shell configuration by combining:

```text
Shell Configuration
  + Shell Facts
  + Toolchain selection
  + Workspace target
  -> Shell Manager request
```

Shell Configuration alone cannot prove a shell is available. Shell Facts alone cannot decide the user's preferred shell. Shell Runtime combines both and calls Shell Manager.

## 6. Persistence Rule

Vityo may persist IDE-owned shell configuration in its DataStore or project/workspace settings.

Vityo must not persist changes into OS global shell configuration, OS global environment variables, shell rc files, or user login shell settings unless a future explicit user-driven tool provides that behavior.

Current implementation path:

```text
ShellConfiguration
  -> ShellConfigurationStore
    -> Configuration Store
      -> Foundation DataStore
        -> File System Manager
```

`ShellConfigurationStore` stores user/workspace shell runtime configuration as ordinary Configuration records. The stored record includes default profile id, profile executable path, shell family, arguments, profile-local environment, global shell environment overlay, login/interactive flags, and timeout.

This persisted configuration is still only an IDE-owned preference. Shell Runtime must combine it with Shell Facts before launching anything because configuration alone cannot prove that a shell exists on the current host.
