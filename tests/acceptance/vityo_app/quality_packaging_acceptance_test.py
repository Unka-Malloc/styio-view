"""REQ-IDE-008 frozen independent desktop release acceptance.

Observation target:
  packaging/vityo/desktop_delivery.py and the three platform manifests.

Precondition:
  one repository delivery contract plus synthetic launch/capability evidence.

Action:
  validate repository wiring, evaluate missing-host and malformed-evidence
  lanes, then evaluate each platform's complete evidence independently.

Oracle:
  all manifests and CI lanes are Vityo-owned; unavailable host tooling is
  BLOCKED rather than passed; incomplete or dishonest launch evidence fails;
  only evidence proving artifact, launch, workspace open, and truthful
  capability reporting passes.
"""

from __future__ import annotations

import importlib.util
import json
import pathlib
import sys
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[3]
MODULE_PATH = ROOT / "packaging" / "vityo" / "desktop_delivery.py"
SOURCE_BINDING = {
    "commit": "a" * 40,
    "source_fingerprint": "b" * 64,
}


def _load_module():
    spec = importlib.util.spec_from_file_location("vityo_desktop_delivery", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("desktop delivery module is unavailable")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class QualityPackagingAcceptanceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.delivery = _load_module()

    def test_repository_declares_three_truthful_vityo_delivery_lanes(self) -> None:
        errors = self.delivery.validate_repository(ROOT)
        self.assertEqual(errors, [], "\n".join(errors))
        contract = self.delivery.load_delivery_contract(ROOT)
        self.assertEqual(
            set(contract["platforms"]),
            {"windows", "macos", "linux"},
        )
        self.assertEqual(contract["product"], "vityo")

        package_script = (ROOT / "scripts" / "package-nightly.py").read_text(
            encoding="utf-8"
        )
        self.assertIn('stage = Path(raw_stage) / "Vityo-Nightly"', package_script)
        self.assertIn('app_root = stage / "opt/vityo"', package_script)

    def test_missing_host_is_blocked_and_incomplete_evidence_fails(self) -> None:
        blocked = self.delivery.evaluate_lane(
            platform="macos",
            host_platform="windows",
            available_tools=set(),
            evidence=None,
        )
        self.assertEqual(blocked.status, "blocked")
        self.assertIn("host", blocked.reason.lower())

        incomplete = self.delivery.evaluate_lane(
            platform="windows",
            host_platform="windows",
            available_tools={"flutter", "python", "powershell"},
            evidence={
                "schema_version": 1,
                "platform": "windows",
                **SOURCE_BINDING,
                "artifact_verified": True,
                "launched": True,
                "workspace_opened": False,
                "capabilities": {},
            },
        )
        self.assertEqual(incomplete.status, "failed")
        self.assertIn("workspace", incomplete.reason.lower())

        dishonest = self.delivery.evaluate_lane(
            platform="linux",
            host_platform="linux",
            available_tools={"flutter", "python", "dpkg-deb", "xvfb-run"},
            evidence={
                "schema_version": 1,
                "platform": "linux",
                **SOURCE_BINDING,
                "artifact_verified": True,
                "launched": True,
                "workspace_opened": True,
                "capabilities": {"agent": "available"},
            },
        )
        self.assertEqual(dishonest.status, "failed")
        self.assertIn("capabilit", dishonest.reason.lower())

    def test_complete_evidence_is_required_for_every_platform(self) -> None:
        required_tools = {
            "windows": {"flutter", "python", "powershell"},
            "macos": {"flutter", "python", "hdiutil"},
            "linux": {"flutter", "python", "dpkg-deb", "xvfb-run"},
        }
        for platform in ("windows", "macos", "linux"):
            with self.subTest(platform=platform):
                result = self.delivery.evaluate_lane(
                    platform=platform,
                    host_platform=platform,
                    available_tools=required_tools[platform],
                    evidence={
                        "schema_version": 1,
                        "platform": platform,
                        **SOURCE_BINDING,
                        "artifact_verified": True,
                        "launched": True,
                        "workspace_opened": True,
                        "capabilities": {
                            "editor": "available",
                            "workspace": "available",
                            "agent": "unavailable",
                            "agent_reason": "No Agent descriptor is configured.",
                        },
                    },
                )
                self.assertEqual(result.status, "passed", json.dumps(result.to_json()))


if __name__ == "__main__":
    unittest.main()
