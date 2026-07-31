#!/usr/bin/env python3
from __future__ import annotations

import os
import subprocess
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "scripts" / "serve-flutter-web-preview.sh"


class WebPreviewSecurityTest(unittest.TestCase):
    def test_non_loopback_bind_is_rejected_before_server_start(self) -> None:
        script = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("127.0.0.1|localhost|::1", script)
        self.assertIn("must be loopback", script)
        if os.name == "nt":
            return

        process = subprocess.run(
            [
                "bash",
                SCRIPT.relative_to(REPO_ROOT).as_posix(),
                "--host",
                "public.example.test",
                "--skip-build",
            ],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )

        self.assertNotEqual(process.returncode, 0)
        self.assertIn("must be loopback", process.stderr)


if __name__ == "__main__":
    unittest.main()
