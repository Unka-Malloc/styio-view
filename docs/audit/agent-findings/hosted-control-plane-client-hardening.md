# View Hosted Control Plane Client Hardening

**Purpose:** Record hosted control-plane IO hardening findings from the parallel external audit pass.

**Last updated:** 2026-04-22

**Date:** 2026-04-22

**Date:** 2026-04-22
**Scope owner:** hosted control-plane IO client
**Status:** Remediated for `frontend/vityo_app/lib/src/backend_toolchain/hosted_control_plane_io.dart`

## Findings Addressed

- `VIEW-AUD-003`: IO hosted requests now have a token requirement, bearer auth header, request timeout, and bounded response reads.
- `VIEW-AUD-007`: IO response decoding now handles non-2xx status, malformed JSON, non-object bodies, and malformed envelope fields before adapter decoding.
- `VIEW-AUD-011`: IO endpoint construction now uses validated `Uri` path segments instead of string concatenation and rejects unsafe route segments.

## Remediation

- Base URLs are normalized from `VITYO_HOSTED_URL` and must be absolute `https`, or `http` only for loopback local development. Credentials, query strings, fragments, and relative path segments are rejected.
- Hosted IO routes require `VITYO_HOSTED_TOKEN`; requests send `Authorization: Bearer ...`, `Accept: application/json`, and disable redirects so auth is not forwarded through redirect chains.
- Requests use `VITYO_HOSTED_TIMEOUT_MS` when provided, otherwise a 15 second default. The timeout is applied to connection and whole request/response handling.
- Response reads are bounded by `VITYO_HOSTED_MAX_RESPONSE_BYTES` when provided, otherwise a 1 MiB default. Both declared `contentLength` and streamed chunks are checked.
- Successful responses must be JSON objects. Optional top-level envelope fields used by hosted adapters are type-checked.

## Test Evidence

- `dart analyze lib/src/backend_toolchain/hosted_control_plane_io.dart test/hosted_control_plane_io_hardening_test.dart test/hosted_control_plane_client_test.dart` passed.
- `flutter test test/hosted_control_plane_io_hardening_test.dart` passed with coverage for token requirement, auth/header emission, base URL path construction, non-2xx failure, timeout failure, response-size failure, non-object body failure, non-JSON success response failure, and malformed envelope field failure.
- `flutter test test/hosted_control_plane_client_test.dart` passed, including the existing end-to-end hosted adapter contract path with bearer auth assertions.

## Remaining Risks

- Web hosted-control-plane request hardening remains outside this shard.
- The token source is environment-only; rotation/refresh and secure platform credential storage are not modeled here.
- Higher-level adapters still surface some hosted IO failures as raw exceptions rather than a uniform adapter failure envelope.
- Live hosted product-gate tests were not run in this remediation pass.
