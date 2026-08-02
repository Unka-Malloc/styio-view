"""Acceptance freeze for IDE full-harness readiness (Node 63016713).

Criteria mapping (observation dimensions selected only where applicable):

0 plan-only / preflight — success + boundary: complete REQ-IDE-001..008 once,
  no suite/Agent/receipt side effects.
1 fail-closed receipts — success + negative + fingerprint: every formal exit
  emits one bounded atomic receipt with eight slots and digests.
2 portability — privacy/boundary: no hard-coded Better Plan / home / sibling
  checkout path; Better Plan remains lifecycle-owned.
3 focused proof — replay of declared focused commands without real ide/full.

These tests inspect plan/preflight output and synthetic receipts only. They
never execute the one-time ``ide/full`` regression.
"""

from __future__ import annotations

import importlib.util
import json
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[3]
QUALITY_SCRIPT = ROOT / "scripts" / "vityo_quality.py"
RECEIPT_SCRIPT = ROOT / "scripts" / "vityo_validation_receipt.py"
DEFAULT_RECEIPT = ROOT / "artifacts" / "validation" / "vityo-full.json"
REQUIRED = tuple(f"REQ-IDE-{index:03d}" for index in range(1, 9))
STABLE_CODES = (
    "invalid_requirement_mapping",
    "source_path_missing",
    "tool_unavailable",
    "unsupported_host",
    "commit_unavailable",
    "dirty_candidate",
    "duplicate_candidate_receipt",
    "receipt_destination_unavailable",
    "suite_failed",
    "source_fingerprint_drift",
    "validation_harness_failed",
    "receipt_write_failed",
)
FORBIDDEN_PATH_MARKERS = (
    'ROOT.parent / "better-plan"',
    "ROOT.parent / 'better-plan'",
    'Path.home() / "better-plan"',
    "Path.home() / 'better-plan'",
    "/better-plan/scripts/manifest_tool",
)


def _load_module(name: str, relative_path: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {relative_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


receipt = _load_module(
    "vityo_validation_receipt_acceptance",
    "scripts/vityo_validation_receipt.py",
)
quality = _load_module(
    "vityo_quality_acceptance",
    "scripts/vityo_quality.py",
)


def _run_ide_full(*extra: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            "scripts/vityo_quality.py",
            "--product",
            "ide",
            "--suite",
            "full",
            *extra,
        ],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )


def _canonical_outcomes() -> dict[str, dict[str, object]]:
    return {
        requirement: {
            "status": "passed",
            "suite": f"suite-{index}",
            "duration_ms": index,
        }
        for index, requirement in enumerate(REQUIRED, start=1)
    }


class IdeFullRunnerAcceptanceTest(unittest.TestCase):
    def test_plan_only_is_complete_deterministic_and_side_effect_free(self) -> None:
        before = (
            DEFAULT_RECEIPT.read_bytes() if DEFAULT_RECEIPT.exists() else None
        )
        completed = _run_ide_full("--plan-only")
        self.assertEqual(completed.returncode, 0, completed.stderr)
        payload = json.loads(completed.stdout)
        self.assertEqual(payload["schema_version"], 1)
        self.assertEqual(payload["product"], "vityo")
        self.assertEqual(payload["suite"], "full")
        self.assertEqual(payload["mode"], "plan_only")
        mappings = payload["requirements"]
        self.assertEqual(
            [item["requirement"] for item in mappings],
            list(REQUIRED),
        )
        self.assertEqual(len({item["suite"] for item in mappings}), 8)
        encoded = json.dumps(payload, sort_keys=True).lower()
        self.assertNotIn("coding-agent/full", encoded)
        self.assertNotIn("vityo_coding_agent", encoded)
        after = (
            DEFAULT_RECEIPT.read_bytes() if DEFAULT_RECEIPT.exists() else None
        )
        self.assertEqual(after, before)

    def test_preflight_is_side_effect_free_and_lists_canonical_plan(self) -> None:
        before = (
            DEFAULT_RECEIPT.read_bytes() if DEFAULT_RECEIPT.exists() else None
        )
        completed = _run_ide_full("--preflight")
        self.assertIn(
            completed.returncode,
            {0, 1},
            completed.stderr or completed.stdout,
        )
        payload = json.loads(completed.stdout)
        self.assertEqual(payload["schema_version"], 1)
        self.assertEqual(payload["product"], "vityo")
        self.assertEqual(payload["suite"], "full")
        self.assertEqual(payload["mode"], "preflight")
        self.assertIn(payload["ready"], (True, False))
        if completed.returncode == 0:
            self.assertTrue(payload["ready"])
        else:
            self.assertFalse(payload["ready"])
            self.assertIn(payload.get("failure_code"), STABLE_CODES)
        mappings = payload["requirements"]
        self.assertEqual(
            [item["requirement"] for item in mappings],
            list(REQUIRED),
        )
        self.assertEqual(len({item["suite"] for item in mappings}), 8)
        checks = payload["checks"]
        self.assertIsInstance(checks, list)
        self.assertGreaterEqual(len(checks), 8)
        names = [item["name"] for item in checks]
        self.assertEqual(
            names[:8],
            [
                "requirement_mapping",
                "source_paths",
                "tools",
                "host",
                "commit",
                "digests",
                "duplicate_receipt",
                "receipt_destination",
            ],
        )
        after = (
            DEFAULT_RECEIPT.read_bytes() if DEFAULT_RECEIPT.exists() else None
        )
        self.assertEqual(after, before)
        encoded = json.dumps(payload, sort_keys=True)
        for marker in ("Traceback", "Exception", str(pathlib.Path.home())):
            self.assertNotIn(marker, encoded)

    def test_runner_has_no_hard_coded_better_plan_or_home_path(self) -> None:
        source = QUALITY_SCRIPT.read_text(encoding="utf-8")
        for marker in FORBIDDEN_PATH_MARKERS:
            self.assertNotIn(marker, source)
        self.assertNotIn("def _run_plan_validation", source)
        self.assertNotRegex(
            source,
            r"""["']\$HOME["']|os\.environ\[\s*["']HOME["']\s*\]""",
        )
        # Lifecycle ownership may be named; it must not be executed by ide/full.
        ide_full_source = source.split("def ide_full", 1)[1].split(
            "\ndef coding_agent_full",
            1,
        )[0]
        self.assertNotIn("manifest_tool", ide_full_source)
        self.assertNotIn("check-labels", ide_full_source)
        self.assertNotIn("better-plan", ide_full_source.lower())

    def test_receipts_fail_closed_bind_digests_and_write_atomically(self) -> None:
        outcomes = _canonical_outcomes()
        digest = "d" * 64
        payload = receipt.build_ide_receipt(
            start_fingerprint="a" * 64,
            end_fingerprint="a" * 64,
            commit="b" * 40,
            platform="windows",
            outcomes=outcomes,
            protocol_schema_sha256=digest,
            acceptance_fixtures_sha256=digest,
        )
        self.assertEqual(payload["status"], "passed")
        self.assertEqual(tuple(payload["requirements"]), REQUIRED)
        self.assertEqual(payload["protocol_schema_sha256"], digest)
        self.assertEqual(payload["acceptance_fixtures_sha256"], digest)
        self.assertEqual(payload.get("failure_code"), None)
        self.assertNotIn("desktop_lanes", payload)
        for key in (
            "schema_version",
            "product",
            "suite",
            "status",
            "failure_code",
            "commit",
            "platform",
            "source_fingerprint",
            "protocol_schema_sha256",
            "acceptance_fixtures_sha256",
            "requirements",
        ):
            self.assertIn(key, payload)

        with self.assertRaisesRegex(
            receipt.ValidationReceiptError,
            "missing_requirement_outcome",
        ):
            receipt.build_ide_receipt(
                start_fingerprint="a" * 64,
                end_fingerprint="a" * 64,
                commit="b" * 40,
                platform="windows",
                outcomes={
                    key: value
                    for key, value in outcomes.items()
                    if key != "REQ-IDE-008"
                },
                protocol_schema_sha256=digest,
                acceptance_fixtures_sha256=digest,
            )
        with self.assertRaisesRegex(
            receipt.ValidationReceiptError,
            "source_fingerprint_drift",
        ):
            receipt.build_ide_receipt(
                start_fingerprint="a" * 64,
                end_fingerprint="c" * 64,
                commit="b" * 40,
                platform="windows",
                outcomes=outcomes,
                protocol_schema_sha256=digest,
                acceptance_fixtures_sha256=digest,
            )
        with self.assertRaisesRegex(
            receipt.ValidationReceiptError,
            "invalid_evidence_digest",
        ):
            receipt.build_ide_receipt(
                start_fingerprint="a" * 64,
                end_fingerprint="a" * 64,
                commit="b" * 40,
                platform="windows",
                outcomes=outcomes,
                protocol_schema_sha256="not-a-digest",
                acceptance_fixtures_sha256=digest,
            )

        with tempfile.TemporaryDirectory() as directory:
            destination = pathlib.Path(directory) / "ide-full.json"
            receipt.write_receipt_atomic(destination, payload)
            self.assertEqual(
                json.loads(destination.read_text(encoding="utf-8")),
                payload,
            )
            self.assertEqual(
                list(destination.parent.glob(f".{destination.name}.*.tmp")),
                [],
            )

    def test_duplicate_requirement_mapping_is_rejected(self) -> None:
        plan = [
            {
                "requirement": f"REQ-IDE-{index:03d}",
                "suite": f"suite-{index}",
            }
            for index in range(1, 9)
        ]
        plan[-1]["requirement"] = "REQ-IDE-007"
        with self.assertRaisesRegex(
            receipt.ValidationReceiptError,
            "invalid_requirement_mapping",
        ):
            receipt.validate_full_suite_plan(plan)

    def test_source_fingerprint_binds_protocol_and_acceptance_fixtures(self) -> None:
        roots = getattr(quality, "_FINGERPRINT_ROOTS")
        joined = "\n".join(roots)
        self.assertIn("tests/acceptance/vityo_app", joined)
        self.assertIn("packages/vityo_agent_protocol/schema", joined)
        self.assertTrue(hasattr(quality, "_protocol_schema_digest"))
        self.assertTrue(hasattr(quality, "_acceptance_fixtures_digest"))
        protocol = quality._protocol_schema_digest()
        fixtures = quality._acceptance_fixtures_digest()
        self.assertRegex(protocol, r"^[0-9a-f]{64}$")
        self.assertRegex(fixtures, r"^[0-9a-f]{64}$")

    def test_formal_full_never_invoked_by_this_acceptance_module(self) -> None:
        # Guardrail for criterion 3: this file must not spawn bare ide/full.
        source = pathlib.Path(__file__).read_text(encoding="utf-8")
        bare = re.findall(
            r"_run_ide_full\(\s*\)|_run_ide_full\(\s*\[\]\s*\)",
            source,
        )
        self.assertEqual(bare, [])
        receipt_flag = "--" + "receipt"
        for match in re.finditer(r"_run_ide_full\((.*?)\)", source, re.S):
            self.assertNotIn(receipt_flag, match.group(1))


if __name__ == "__main__":
    unittest.main()
