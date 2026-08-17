# Vityo Nightly desktop packages

`release-versions.json` versions the Vityo core and each desktop adapter
independently. `scripts/package-nightly.py --platform <platform>` consumes one
platform definition and writes only that platform's artifact and receipt under
`build/nightly/`.

| Platform | Artifact | Install/start gate |
|---|---|---|
| Linux | Debian package | `dpkg -i`, then launch through Xvfb |
| Windows | ZIP with per-user PowerShell installer | install to a temporary per-user directory, launch, uninstall |
| macOS | DMG | verify, mount, copy the app bundle, launch |

The three native CI jobs do not depend on one another. A platform failure blocks
only that adapter artifact. Each artifact receipt records both the core version
and that platform adapter version. Each package also carries one
`vityod-component.json` next to its daemon executable. That identity binds the
target, daemon version, protocol range, executable digest, daemon-source
fingerprint, declared runtime libraries, and application-relative location.

`python3 scripts/vityod-desktop-matrix-gate.py --fixtures-only` verifies all
three structural lanes without claiming a launch. A matching host validates an
installed layout with `--platform <platform> --application-root <path>`; that
lane checks the component digest, daemon health, and two consecutive client
handshakes against the same daemon instance.

Nightly signing is currently an explicit release gap on all three platforms.
Until a platform definition reports configured signing, its automatic update
policy must remain `false`; the release-readiness gate enforces this fail-closed.
An unsigned artifact is for manual trust/install testing and is not evidence of
a completed product capability.
