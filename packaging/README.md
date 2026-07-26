# Styio IDE Nightly desktop packages

`release-versions.json` versions the Styio IDE core and each desktop adapter
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
and that platform adapter version.

Nightly signing is currently an explicit release gap on all three platforms.
Until a platform definition reports configured signing, its automatic update
policy must remain `false`; the release-readiness gate enforces this fail-closed.
An unsigned artifact is for manual trust/install testing and is not evidence of
a completed product capability.
