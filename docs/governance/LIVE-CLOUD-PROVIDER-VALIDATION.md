# Live Cloud Provider Validation

**Purpose:** Define an opt-in validation path for cloud providers owned by a compatible Agent runtime, without storing raw credentials or treating live-provider evidence as default CI evidence.

**Last updated:** 2026-07-30

## Scope

Live cloud provider validation is optional evidence for the Agent-runtime delivery track. It verifies
that a configured provider can be reached through the Coding Agent provider router and that Vityo
receives only the resulting structured Agent protocol state. It is not evidence that the IDE
connects to a provider.

The Flutter test command below is preserved only as legacy migration evidence. New live-provider
validation belongs under `products/vityo_coding_agent`; the IDE-side route must be removed by the
atomic migration recorded in
[Vityo Implementation Gaps](../design/Vityo-Implementation-Gaps.md).

This lane is not part of default local CI, pull request CI, or checkpoint health. Default CI must continue to use deterministic loopback, mocked transport, and credential-store tests.

## Opt-In Requirements

A live validation run must satisfy all of these conditions:

1. The runner sets an explicit opt-in flag such as `VITYO_LIVE_AGENT_PROVIDER=1`.
2. The provider endpoint is configured through an Agent-runtime provider route, not through Vityo
   settings or ad hoc IDE HTTP code.
3. Credentials are injected through the Agent runtime's credential boundary, a runner secret, or a
   short-lived environment secret; Vityo receives no raw credential.
4. Raw credential values are never written to logs, release notes, screenshots, artifacts, or `docs/release/local-validation-evidence.md`.
5. The evidence record captures only redacted credential readiness, provider route, protocol family, model id, request id, response status, failure category, and recovery action.

## Evidence Rules

When the opt-in lane runs, record evidence in `docs/release/local-validation-evidence.md` only if the run produces a structured result:

- **Passed:** route resolution ready, credential readiness ready, request completed, provider message id present, and response content adapted into an agent response.
- **Blocked:** route resolution blocked, credential missing, provider endpoint unreachable, policy disallowed client credential lookup, or hosted route requires server-side credential resolution.
- **Failed:** request reached the provider but returned a protocol, authentication, quota, timeout, or response-shape error.

Do not record a live provider as release evidence when the opt-in flag is absent. Do not convert loopback provider tests into live-provider evidence.

## Recommended Local Command Shape

Legacy IDE-route deterministic tests remain useful only until migration:

```bash
cd products/vityo_app
flutter test --no-pub \
  test/agent_provider_route_executor_test.dart \
  test/agent_provider_credential_resolver_test.dart \
  test/agent_provider_live_local_e2e_test.dart
```

An eventual live test or workflow must require the opt-in flag and must exit as skipped or blocked when the flag or credential is missing. It must not fail default CI because a developer lacks cloud credentials.

## Release Checklist

Before treating a live provider run as release evidence:

1. Confirm the lane was explicitly opted in.
2. Confirm raw credentials are absent from console logs and uploaded artifacts.
3. Confirm the result includes a structured provider route resolution.
4. Confirm failures include a user-visible recovery action, such as opening provider settings or selecting a fallback provider.
5. Link the live result to a dated release evidence row.
