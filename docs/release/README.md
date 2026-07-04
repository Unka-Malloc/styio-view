# Release Evidence

**Purpose:** Define the release evidence directory for Vityo platform packaging, local validation ledgers, and launch closure requirements.

**Last updated:** 2026-06-29

## Scope

This directory stores release-facing evidence and platform packaging requirements. It is not a substitute for a formal product release record. A release checkpoint can cite these files for local validation, CI floor, packaging requirements, known blockers, and unsupported routes.

Formal launch closure still requires the release owner to attach production artifacts, packaging or signing evidence, install/update/uninstall proof, rollback or recovery proof, and release notes for every claimed platform.

## Current Files

- [local-validation-evidence.md](./local-validation-evidence.md) records local gate evidence and blockers observed on this branch.
- [linux-release-packaging.md](./linux-release-packaging.md) defines Linux desktop packaging requirements.
- [windows-release-packaging.md](./windows-release-packaging.md) defines Windows desktop packaging requirements.

## Rules

1. Do not treat prototype evidence as production launch evidence.
2. Do not mark Better Plan terminal release checkpoints completed from documentation alone.
3. Record blocked gates with the exact environment constraint or external dependency.
4. Refresh generated docs indexes after adding or renaming release evidence files.
