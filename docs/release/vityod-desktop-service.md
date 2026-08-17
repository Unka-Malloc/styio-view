# Vityod desktop service delivery

**Purpose:** Define build, staging, launch, recovery, upgrade, rollback, uninstall retention, and evidence rules for the packaged desktop daemon.

**Last updated:** 2026-08-10

Vityo desktop packages contain exactly one target-matching `vityod` binary. The
binary is an application component, starts on demand for the current user, and
is never discovered through an unrestricted executable search path. Web and
mobile builds do not load it.

## Build and staging

Build the locked Rust workspace in release mode before finalizing the Flutter
bundle. The platform package manifest fixes both the Rust target and the
application-relative destination. Packaging must reject a missing, extra,
stale, or target-mismatched component. Fixture lanes prove structure only and
must never claim native launch evidence.

The adjacent `vityod-component.json` records the daemon version, protocol
range, native target, executable SHA-256, deterministic daemon-source
fingerprint, required runtime libraries, and installed relative path. The
launcher and installer use only the platform-declared path; the manifest does
not contain a machine path, endpoint, credential, or user identifier.

## Launch and recovery

The Flutter launcher connects to a healthy compatible per-user instance or
starts the adjacent manifest-bound binary. Protocol and capability negotiation
complete before workspace state is exposed. A disconnected UI reconnects from
its last acknowledged event cursor; an unavailable suffix causes an explicit
full resynchronization. A daemon restart truthfully terminates resources that
cannot survive it, including live PTYs.

## Upgrade and rollback

An upgrade first requests quiescence, refuses silent replacement during an
unsafe commit, checkpoints durable state, and validates the new binary,
protocol, database integrity, and reconnect path. Failed validation restores
the previous binary and readable checkpoint. Active work that cannot be
preserved requires a surfaced user decision; packaging simulations do not make
that decision or mutate live data.

The release regression exercises this ordering through
`packaging/vityo/lifecycle.py`. Compatible same-version or one-step additive
schema changes may commit after quiescence and health validation. Incompatible
versions stop at the version gate; active PTYs, tasks, Agent sessions, or
transactions stop at quiescence; interruption and failed health restore the
checkpoint projection. This is a fixture-only policy simulation, not authority
to replace a live binary or database.

## Uninstall and retained state

Uninstall removes application components and launch metadata but retains
workspaces, acknowledged dirty-buffer checkpoints, transaction journals,
settings, and credential references. Data reclamation is a separate explicit
user-confirmed operation. Raw credentials and terminal streams are not part of
the durable daemon database or package evidence.

The Windows per-user installer validates the component digest and health before
activation, stages beside the destination, retains the previous application as
a rollback candidate, and removes that candidate only after installed health
succeeds. The uninstaller removes only the application destination and Start
Menu shortcut. Linux package-manager state and a copied macOS application use
their platform-native replacement paths; formal signed distribution evidence
remains blocked by the signing gaps declared in the platform manifests.

## Evidence

Run `python3 scripts/vityod-desktop-matrix-gate.py --fixtures-only` on any host.
Only a matching native release host may run
`python3 scripts/vityod-desktop-matrix-gate.py --platform <platform>
--application-root <installed-app-root>`. The native lane verifies exactly one
manifest-bound daemon, executable and source digests, target, protocol, health,
and disconnect/reconnect through two fresh authenticated client handshakes.
The separate application delivery receipt binds the app commit and source
fingerprint, package launch, workspace open, and truthful capabilities; both
checks are required by the native CI lane.
