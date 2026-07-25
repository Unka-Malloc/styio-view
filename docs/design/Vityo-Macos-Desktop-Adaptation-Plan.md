# Vityo macOS Desktop Adaptation Plan

**Purpose:** Preserve macOS desktop open-work signals cited by convergence checkpoints; do not fork domain logic.

**Last updated:** 2026-07-11

**Status:** Restored citation anchor

**Authoritative successors:** Vityo-System-Architecture.md, Vityo-Implementation-Gaps.md, REQ-007.

## Open-work signals (line-stable for checkpoint citations)
























macOS adaptation must not fork domain logic. Platform-specific behavior belongs in Platform Manager, File System Manager, process/terminal adapters, package policy, or capability snapshots.











| Execution | Bash/zsh/process launches use environment overlays, timeout, redaction, cancellation, and app-policy blocked states. |





















macOS-specific implementation must prove:






6. App sandbox or entitlement limitations become blocked states with recovery guidance.
