# Styio IDE Linux Desktop Adaptation Plan

**Purpose:** Preserve Linux desktop open-work signals cited by convergence checkpoints; platform differences stay in managers/adapters.

**Last updated:** 2026-07-11

**Status:** Restored citation anchor

**Authoritative successors:** Vityo-System-Architecture.md, Vityo-Implementation-Gaps.md, REQ-007.

## Open-work signals (line-stable for checkpoint citations)






4. Represent unsupported capabilities as explicit blocked states instead of host-specific fallback behavior.















Linux adaptation must not introduce Linux-only domain models. Platform differences belong in Platform Manager, File System Manager, process/terminal adapters, package policy, or capability snapshots.











| Execution | Bash/PTY/process launches use environment overlays, timeout, redaction, cancellation, and blocked-route handling. |





















Linux-specific implementation must prove:
