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

## Compatibility And Product Boundaries

- [ ] Public schema or contract change is documented in `docs/governance/API-COMPATIBILITY.md`
- [ ] Deprecation has replacement path, removal target, and release-note impact
- [ ] Product-line boundaries pass `python3 scripts/check_product_line_boundaries.py`
- [ ] Removed package identities or forwarding roots were not recreated

## Security And Performance

- [ ] Sandbox, secret, redaction, module manifest security, or agent permission changes are documented
- [ ] Security-sensitive changes pass `python3 scripts/check_security_baseline.py`
- [ ] Performance-sensitive changes pass `python3 scripts/check_performance_budgets.py`
- [ ] Benchmark regression evidence is attached when `scripts/performance-gate.py` applies

## Validation

- [ ] `python3 scripts/docs-index.py --write`
- [ ] `python3 -m pytest tests/test_docs_tooling_coverage.py`
- [ ] `python3 scripts/check_architecture_boundaries.py`
- [ ] `python3 scripts/check_product_line_boundaries.py`
- [ ] `python3 scripts/check_security_baseline.py`
- [ ] `python3 scripts/check_performance_budgets.py`
- [ ] `python3 scripts/release-readiness-gate.py --skip-build`
- [ ] `git diff --check`

## Residual Risk

- 
