# Observable Delivery Follow-Ups

**Purpose:** Point Vityo agents at the unapproved observable-graph follow-ups, especially the execution-adapter envelope mismatch that drops real Pafio receipts.

**Last updated:** 2026-09-06

**Status:** Unapproved. Do not implement these items from this rollup.

The full cross-repo list lives in the Styio rollup `docs/rollups/OBSERVABLE-DELIVERY-FOLLOW-UPS.md` on `styio-nightly`. Vityo-owned entries:

1. **Serious.** `execution_adapter_io.dart` expects a `workflow_payload_version` envelope that Pafio never emits. Real Pafio sessions lose receipt and diagnostics.
2. **Medium.** Publishing identical snapshot bytes leaves the Observable panel stuck at `refreshing`.
3. Language and compiler follow-ups (lineage producers, wait-reason runtime, S3 budget approval) are Styio-owned and stay unapproved here.
