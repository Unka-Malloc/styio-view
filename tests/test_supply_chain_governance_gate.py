#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
GATE_PATH = REPO_ROOT / "scripts" / "supply-chain-governance-gate.py"


def load_gate_module():
    spec = importlib.util.spec_from_file_location(
        "supply_chain_governance_gate",
        GATE_PATH,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {GATE_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class SupplyChainGovernanceGateTest(unittest.TestCase):
    def setUp(self) -> None:
        self.gate = load_gate_module()

    def _write_file(self, root: Path, relative_path: str, text: str = "placeholder\n") -> None:
        path = root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def _write_minimal_tree(self, root: Path) -> None:
        workflow = (
            "name: audit\n"
            "on:\n"
            "  pull_request:\n"
            "permissions:\n"
            "  contents: read\n"
            "jobs:\n"
            "  audit:\n"
            "    runs-on: ubuntu-latest\n"
            "    steps:\n"
            "      - uses: actions/checkout@0123456789abcdef0123456789abcdef01234567\n"
            "      - run: python3 scripts/supply-chain-governance-gate.py\n"
            "      - run: python3 scripts/dependency-policy-gate.py\n"
            "      - run: python3 scripts/github-actions-pin-gate.py --mode audit\n"
            "      - run: python3 scripts/check_security_baseline.py\n"
            "      - run: python3 scripts/check_license_policy.py\n"
        )
        self._write_file(root, ".github/workflows/audit.yml", workflow)
        self._write_file(root, ".github/workflows/repo-hygiene.yml", workflow)
        self._write_file(
            root,
            ".github/dependabot.yml",
            "version: 2\n"
            "updates:\n"
            "  - package-ecosystem: \"github-actions\"\n"
            "    directory: \"/\"\n"
            "    schedule:\n"
            "      interval: \"weekly\"\n"
            "    open-pull-requests-limit: 5\n"
            "  - package-ecosystem: \"pub\"\n"
            "    directory: \"/frontend/vityo_app\"\n"
            "    schedule:\n"
            "      interval: \"weekly\"\n"
            "    open-pull-requests-limit: 5\n"
            "  - package-ecosystem: \"npm\"\n"
            "    directory: \"/prototype\"\n"
            "    schedule:\n"
            "      interval: \"weekly\"\n"
            "    open-pull-requests-limit: 5\n",
        )
        self._write_file(
            root,
            ".gitignore",
            "/.env\n/.env.*\n*.pem\n*.key\n*.p12\n*.pfx\n",
        )
        self._write_file(
            root,
            "DEPENDENCY-USAGE.md",
            "# Dependency Usage Boundary\n\n"
            "## Runtime Dependencies\n"
            "| Dependency | Version | License | Source Boundary | Usage Boundary |\n"
            "## Dev Dependencies\n"
            "## Prototype Dependencies\n"
            "## Build / CI / Platform Toolchain Dependencies\n",
        )
        self._write_file(root, "LICENSE-POLICY.md")
        self._write_file(
            root,
            "docs/governance/SECURITY-AND-SUPPLY-CHAIN.md",
            "Dependabot\n"
            "scripts/supply-chain-governance-gate.py\n"
            "scripts/github-actions-pin-gate.py\n"
            "scripts/dependency-policy-gate.py\n"
            "scripts/check_security_baseline.py\n"
            "scripts/check_license_policy.py\n",
        )
        self._write_file(root, "docs/specs/THIRD-PARTY.md")
        self._write_file(root, "frontend/vityo_app/pubspec.lock")
        self._write_file(root, "prototype/package-lock.json", json.dumps({"lockfileVersion": 3}))
        for script in self.gate.REQUIRED_GATE_SCRIPTS:
            self._write_file(root, script.as_posix(), "#!/usr/bin/env python3\n")

    def test_minimal_governance_tree_passes(self) -> None:
        with tempfile.TemporaryDirectory(prefix="supply-chain-", dir=REPO_ROOT) as tmp_name:
            root = Path(tmp_name)
            self._write_minimal_tree(root)

            results = self.gate.collect_checks(root)

        failures = [result for result in results if not result.ok and result.severity == "error"]
        self.assertEqual(failures, [])

    def test_workflow_security_rejects_write_permissions_and_pull_request_target(self) -> None:
        with tempfile.TemporaryDirectory(prefix="supply-chain-", dir=REPO_ROOT) as tmp_name:
            root = Path(tmp_name)
            self._write_minimal_tree(root)
            self._write_file(
                root,
                ".github/workflows/audit.yml",
                "name: audit\n"
                "on:\n"
                "  pull_request_target:\n"
                "permissions:\n"
                "  contents: write\n",
            )

            results = self.gate.collect_checks(root)

        joined = "\n".join(result.detail for result in results if not result.ok)
        self.assertIn("contents: write", joined)
        self.assertIn("pull_request_target is not allowed", joined)

    def test_dependabot_requires_governed_ecosystems(self) -> None:
        with tempfile.TemporaryDirectory(prefix="supply-chain-", dir=REPO_ROOT) as tmp_name:
            root = Path(tmp_name)
            self._write_minimal_tree(root)
            self._write_file(
                root,
                ".github/dependabot.yml",
                "version: 2\n"
                "updates:\n"
                "  - package-ecosystem: \"github-actions\"\n"
                "    directory: \"/\"\n"
                "    schedule:\n"
                "      interval: \"weekly\"\n",
            )

            results = self.gate.collect_checks(root)

        failed_names = {result.name for result in results if not result.ok}
        self.assertIn("dependabot update: pub /frontend/vityo_app", failed_names)
        self.assertIn("dependabot update: npm /prototype", failed_names)

    def test_secret_scan_flags_high_signal_tokens(self) -> None:
        with tempfile.TemporaryDirectory(prefix="supply-chain-", dir=REPO_ROOT) as tmp_name:
            root = Path(tmp_name)
            self._write_minimal_tree(root)
            self._write_file(
                root,
                "scripts/leaky.sh",
                "TOKEN=ghp_0123456789abcdefghijklmnopqrstuvwxyzABC\n",
            )

            results = self.gate.collect_checks(root)

        self.assertTrue(
            any(not result.ok and "GitHub classic token" in result.detail for result in results),
            results,
        )


if __name__ == "__main__":
    unittest.main()
