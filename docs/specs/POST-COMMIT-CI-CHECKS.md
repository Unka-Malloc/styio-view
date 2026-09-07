# Post-Commit CI Checks

**Purpose:** Define the required workflow for checking GitHub Actions after a local commit is pushed, including what must be verified before committing and what must be watched after pushing.

**Last updated:** 2026-09-08

## Scope

This spec applies to agent and maintainer work on `Vityo` branches. It covers local pre-commit verification, post-push GitHub Actions monitoring, and failure recovery for repository-local and cross-repository gates.

Use the current request and existing approvals to determine authority. This workflow does not itself authorize a commit, push, merge, release, or governance change. Repository review and approval requirements remain effective; do not ask again for an action already covered by the same scope and risk boundary. Resolve discoverable facts and ordinary in-scope implementation issues directly, report material findings, and pause only work that needs a new decision.

## Commit-Time Verification

Before creating an authorized commit, run the closest local checks affected by the change. Use focused checks during implementation and reuse passing evidence while its inputs remain unchanged. The commands below are a scope-dependent catalog, not a requirement to run every gate before every commit.

Local checks for the affected surfaces:

```bash
python3 scripts/repo-hygiene-gate.py --mode tracked
./scripts/docs-gate.sh
./scripts/delivery-gate.sh --mode checkpoint --skip-health
```

Product-gate tests remain explicit extension checks unless the user requests them or CI is configured to require them:

```bash
VITYO_PRODUCT_GATE=1 flutter test
```

Cross-repository contract or product changes must also run the matching ecosystem gate from the `SymPolicy/Styio` checkout, named `styio-nightly` in CI, for example:

```bash
cd <styio-workspace>
python3 scripts/ecosystem-cli-doc-gate.py --require-workspace --workspace-root <workspace-root>
cd <vityo-workspace>
python3 scripts/ecosystem-product-gate.py --require-real-matrix --platform <platform> --pafio-bin <pafio> --styio-bin <styio>
```

The commit message body should record the checks that were actually run.

## Final Regression

Run the required complete regression once, after all changes, source review, in-scope repairs, and focused verification are finished. Use the delivery health gate without `--skip-health` when that full gate is required. Coordinate local and CI evidence for the same candidate; required CI checks still run after an authorized push. A final complete-regression failure requires a diagnosis and concrete repair and verification proposal for the developer. Do not automatically repair, rerun, or push a repair that would restart this regression before that decision. Continue independent authorized work, and do not mark unresolved acceptance as complete.

## Post-Push Verification

After pushing a commit, the agent must actively check GitHub Actions while the current work turn remains open.

Required steps:

1. Resolve the current branch and pushed commit.
2. Query GitHub Actions for the repository and branch.
3. Observe the relevant run for the exact pushed commit using bounded tool waits and progress updates. An expired observation window does not cancel the run or establish its result.
4. If a check fails, inspect its diagnostics and report a privacy-safe cause and the smallest repair and verification proposal. Follow the Final Regression decision rule for complete-regression failures. Ordinary focused-check failures may be repaired within existing authority; a follow-up commit or push must also be covered by that authority.
5. If observation is blocked or the turn ends before the run completes, report the run URL, commit, unresolved status, and resume command as an incomplete verification handoff.

Preferred commands:

```bash
gh run list --branch "$(git branch --show-current)" --limit 10
gh run view <run-id> --json headSha,status,conclusion,url
gh run view <run-id> --log-failed
```

If `gh` is unavailable or unauthenticated, the agent must state that GitHub Actions could not be checked directly and include the local gates that were run instead.

## Cross-Repository Work

When one delivery touches `SymPolicy/Styio`, `SymPolicy/Pafio`, and `Vityo`, post-push verification applies to every pushed repository. The agent should check each repository's GitHub Actions status, not only the repository that received the last commit.

Cross-repository gates must use the same workspace checkout set that will be visible to CI. If a gate consumes another repository's branch, perform an already-authorized dependency push first; otherwise prepare the required handoff and report the revision mismatch. A gate dependency does not grant permission to publish another repository.

## Delivery Ruleset Governance

Required GitHub merge gates are maintained through GitHub Rulesets, not legacy classic branch protection. `release`, `stable`, and `nightly` must have an active Ruleset requiring the `audit` status check from the `styio-audit` workflow, with strict required status checks enabled. Downstream `nightly` may additionally require pull requests and the repository-local `local-ci-gate`, `windows-native`, and `macos-native` checks before merge. Every other branch name is temporary and must not receive branch-name-specific rules.

Gate audits must inspect effective branch rules, for example:

```bash
gh api repos/SymPolicy/Vityo/rules/branches/release
```

Do not use `branches/<branch>/protection/required_status_checks` as the authority for this repository. That legacy classic endpoint can return 404 even when the Ruleset gate is active.

## Completion Criteria

A delivery requiring remote verification is complete only when the required checks pass for the exact delivered commit and all authorized acceptance conditions are satisfied. After an approved repair and push, use the replacement commit's results.

Queued, running, failed, cancelled, or unobservable checks remain unresolved verification. A status URL and recovery command make the handoff actionable; they do not make the delivery complete. A local-only request is complete against its local acceptance conditions and does not require an unsolicited push.
