## Summary

- 

## Owner Surfaces

- [ ] Architecture / IDE boundary
- [ ] Runtime / agent
- [ ] Module / platform
- [ ] Adapter / contracts
- [ ] Shell / editor
- [ ] Theme / UX
- [ ] Governance / security / release
- [ ] Docs / delivery

## Compatibility And Migration

- [ ] Public schema or contract change is documented in `docs/governance/API-COMPATIBILITY.md`
- [ ] Deprecation has replacement path, removal target, and release-note impact
- [ ] Legacy facade changes pass `python3 scripts/check_compat_facades.py`
- [ ] No new implementation logic was added under compatibility facade roots

## Security And Performance

- [ ] Sandbox, secret, redaction, module manifest security, or agent permission changes are documented
- [ ] Security-sensitive changes pass `python3 scripts/check_security_baseline.py`
- [ ] Performance-sensitive changes pass `python3 scripts/check_performance_budgets.py`
- [ ] Benchmark regression evidence is attached when `scripts/performance-gate.py` applies

## Validation

- [ ] `python3 scripts/docs-index.py --write`
- [ ] `python3 -m pytest tests/test_docs_tooling_coverage.py`
- [ ] `python3 scripts/check_architecture_boundaries.py`
- [ ] `python3 scripts/check_compat_facades.py`
- [ ] `python3 scripts/check_security_baseline.py`
- [ ] `python3 scripts/check_performance_budgets.py`
- [ ] `python3 scripts/release-readiness-gate.py --skip-build`
- [ ] `git diff --check`

## Residual Risk

- 
