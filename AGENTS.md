# Repository Workflow Rules

## Frontend Prototype Preservation

- Never remove the Vityo frontend Prototype in `prototype/`.
- The Prototype is a permanent repository asset. Do not delete it, move it out
  of the repository, rename it to evade this rule, or make its removal part of
  a cleanup, migration, architecture cutover, or release plan.
- Flutter may remain the default production client, but consolidation work must
  preserve the Prototype source, entrypoints, dependency governance, and tests.
- A plan, task, gate, or document that requires Prototype removal conflicts with
  this rule and must be replaced before execution.

## Branch And Pull Request Flow

- Create every commit on a task-specific temporary branch. Do not commit
  directly on `nightly` or another long-lived branch such as `main`, `stable`,
  `release`, or `ai-dev`.
- If work starts while `nightly` is checked out, create and switch to a
  temporary branch before the first commit. Use a name that identifies the
  actor and task, for example `<actor>/<task>`.
- Push temporary branches only to the downstream `origin` repository. Merge a
  temporary branch into downstream `nightly` through a pull request; never
  push it directly to `nightly`.
- An upstream pull request must use downstream `nightly` as its head branch.
  Never open an upstream pull request from a temporary branch, and never push
  a temporary branch to the `upstream` remote.
- Before opening an upstream pull request, first merge the temporary branch
  into downstream `nightly` and verify that the upstream pull request head is
  exactly `Unka-Malloc:nightly`.
