# Live Cloud Provider Validation

**Purpose:** Define the opt-in validation path for real cloud agent providers without storing raw credentials or treating live-provider evidence as default CI evidence.

**Last updated:** 2026-06-29

## Scope

Live cloud provider validation is optional release evidence for agent provider routes. It verifies that a configured OpenAI-compatible cloud endpoint can be reached through Vityo's agent provider adapter, credential resolver, route executor, and structured response adapter.

This lane is not part of default local CI, pull request CI, or checkpoint health. Default CI must continue to use deterministic loopback, mocked transport, and credential-store tests.

## Opt-In Requirements

A live validation run must satisfy all of these conditions:

1. The runner sets an explicit opt-in flag such as `VITYO_LIVE_AGENT_PROVIDER=1`.
2. The provider endpoint is configured through an `AgentPromptProfile` and `AgentProviderEndpoint`, not through ad hoc HTTP code.
3. Credentials are injected through `CredentialDataStore`, a runner secret, or a short-lived environment secret that is immediately bound to a `CredentialReference`.
4. Raw credential values are never written to logs, release notes, screenshots, artifacts, or `docs/release/local-validation-evidence.md`.
5. The evidence record captures only redacted credential readiness, provider route, protocol family, model id, request id, response status, failure category, and recovery action.

## Evidence Rules

When the opt-in lane runs, record evidence in `docs/release/local-validation-evidence.md` only if the run produces a structured result:

- **Passed:** route resolution ready, credential readiness ready, request completed, provider message id present, and response content adapted into an agent response.
- **Blocked:** route resolution blocked, credential missing, provider endpoint unreachable, policy disallowed client credential lookup, or hosted route requires server-side credential resolution.
- **Failed:** request reached the provider but returned a protocol, authentication, quota, timeout, or response-shape error.

Do not record a live provider as release evidence when the opt-in flag is absent. Do not convert loopback provider tests into live-provider evidence.

## Recommended Local Command Shape

Use the existing deterministic tests before any live lane:

```bash
cd frontend/vityo_app
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
