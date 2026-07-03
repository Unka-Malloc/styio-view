# Golden Standard Test Suite

**Purpose:** Define the Vityo client test level that makes a desktop client version submittable.

**Last updated:** 2026-06-29

`test / smoke` runs the fast Flutter application and language-service smoke tests.

`test / golden-standard` runs the full Flutter test suite, restores prototype and Flutter dependencies, and executes the repository docs and checkpoint health gates after all declared platform-adaptation gates pass.

## Local Gate Profile

`vityo-checkpoint-desktop-profile` is the repository-owned adaptation for the Vityo desktop client. It is maintained in this repository through `checkpoint-health.sh`, Flutter test coverage, prototype dependencies, and desktop client release evidence. The organization-level audit only verifies that this local profile is present and covered by `test / golden-standard`.

Required local markers: repo-owned adaptation, checkpoint-health.sh, Flutter, prototype dependencies, desktop client.

## Industry Gate Group

`client / desktop-quality` is the role-specific gate group for the Vityo desktop client. It keeps Flutter tests, desktop platform behavior, dependency restoration, checkpoint health, and docs checks grouped under `test / golden-standard`.

Required evidence markers: flutter test, desktop platform, dependency restore, checkpoint health, docs gate.

## Submit Readiness

A Vityo client version is submittable only when every declared `platform-adaptation / ...-ci-gate`, `test / smoke`, and `test / golden-standard` all pass.
