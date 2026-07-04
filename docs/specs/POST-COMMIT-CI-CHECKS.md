# Post-Commit CI Checks

**Purpose:** Define the required workflow for checking GitHub Actions after a local commit is pushed, including what must be verified before committing and what must be watched after pushing.

**Last updated:** 2026-05-02

## Scope

This spec applies to agent and maintainer work on `Vityo` branches. It covers local pre-commit verification, post-push GitHub Actions monitoring, and failure recovery for repository-local and cross-repository gates.

## Commit-Time Verification

Before creating a commit, the agent must run the closest local equivalent of the GitHub Actions checks affected by the change.

Minimum local checks for normal changes:

```bash
python3 scripts/repo-hygiene-gate.py --mode tracked
./scripts/docs-gate.sh
./scripts/delivery-gate.sh --mode checkpoint
```

Product-gate tests remain explicit extension checks unless the user requests them or CI is configured to require them:

```bash
VITYO_PRODUCT_GATE=1 flutter test
```

Cross-repository contract or product changes must also run the matching ecosystem gate from the `SymPolicy/Styio` checkout, named `styio-nightly` in CI, for example:

```bash
cd <styio-workspace>
python3 scripts/ecosystem-cli-doc-gate.py --workspace-root <workspace-root>
python3 scripts/ecosystem-product-gate.py --workspace-root <workspace-root>
python3 scripts/ecosystem-sample-workflow-gate.py --workspace-root <workspace-root>
```

The commit message body should record the checks that were actually run.

## Post-Push Verification

After pushing a commit, the agent must actively check GitHub Actions while the current work turn remains open.

Required steps:

1. Resolve the current branch and pushed commit.
2. Query GitHub Actions for the repository and branch.
3. Watch the relevant workflow run or check suite until it reaches a terminal state when the expected runtime is reasonable.
4. If a check fails, inspect the failing job logs, identify the smallest fix, run the matching local gate, create a follow-up commit, and push again.
5. If a check is still queued or running when the turn must end, report the run URL, current status, and the command needed to resume checking.

Preferred commands:

```bash
gh run list --branch "$(git branch --show-current)" --limit 10
gh run watch <run-id> --exit-status
gh run view <run-id> --log-failed
```

If `gh` is unavailable or unauthenticated, the agent must state that GitHub Actions could not be checked directly and include the local gates that were run instead.

## Cross-Repository Work

When one delivery touches `SymPolicy/Styio`, `SymPolicy/Pafio`, and `Vityo`, post-push verification applies to every pushed repository. The agent should check each repository's GitHub Actions status, not only the repository that received the last commit.

Cross-repository gates must use the same workspace checkout set that will be visible to CI. If a gate consumes another repository's branch, push that repository first or report that remote CI may still be using an older sibling checkout.

## Delivery Ruleset Governance

Required GitHub merge gates are maintained through GitHub Rulesets, not legacy classic branch protection. `release`, `stable`, and `nightly` must have an active Ruleset requiring the `audit` status check from the `styio-audit` workflow, with strict required status checks enabled. Downstream `nightly` may additionally require pull requests and the repository-local `local-ci-gate`, `windows-native`, and `macos-native` checks before merge. Every other branch name is temporary and must not receive branch-name-specific rules.

Gate audits must inspect effective branch rules, for example:

```bash
gh api repos/SymPolicy/Vityo/rules/branches/release
```

Do not use `branches/<branch>/protection/required_status_checks` as the authority for this repository. That legacy classic endpoint can return 404 even when the Ruleset gate is active.

## Completion Criteria

A pushed change is not complete until one of these is true:

1. GitHub Actions checks passed.
2. GitHub Actions checks failed, the failure was fixed and re-pushed, and the replacement run passed.
3. GitHub Actions could not be observed within the current turn, and the final handoff records the unresolved run status and recovery command.
