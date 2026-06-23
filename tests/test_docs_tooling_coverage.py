#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[1]


def load_script_module(name: str, relative_path: str):
    path = REPO_ROOT / relative_path
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class DocsIndexToolTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tool = load_script_module("docs_index_tool_under_test", "scripts/docs-index.py")

    def _configure_root(self, root: Path) -> None:
        self.tool.ROOT = root
        self.tool.COLLECTION_DIRS = [Path("docs")]
        self.tool.INDEX_META = {
            "docs": ("Docs Index", "Generated inventory for docs."),
        }

    def test_render_index_sorts_directories_before_files_and_strips_markup(self) -> None:
        with tempfile.TemporaryDirectory(prefix="docs-index-", dir=REPO_ROOT) as tmp_name:
            root = Path(tmp_name)
            docs = root / "docs"
            guides = docs / "guides"
            guides.mkdir(parents=True)
            (docs / "README.md").write_text(
                "# Docs\n\n**Purpose:** Docs root.\n\n**Last updated:** 2026-01-01\n",
                encoding="utf-8",
            )
            (docs / "alpha.md").write_text(
                "# Alpha `Doc`\n\n"
                "**Purpose:** Link to [Guide](./guides/README.md) and use | pipe.\n\n"
                "**Last updated:** 2026-01-03\n",
                encoding="utf-8",
            )
            (docs / "zeta.txt").write_text("ignored\n", encoding="utf-8")
            (guides / "README.md").write_text(
                "# Guide **Book**\n\n"
                "**Purpose:** A __team__ `guide`.\n\n"
                "**Last updated:** 2026-01-02\n",
                encoding="utf-8",
            )
            (docs / "empty-dir").mkdir()
            self._configure_root(root)

            rendered = self.tool.render_index(docs)

        self.assertIn("# Docs Index", rendered)
        self.assertIn("**Last updated:** 2026-01-03", rendered)
        self.assertIn("| `guides/` | [Guide Book](./guides/README.md) | A team guide. |", rendered)
        self.assertIn("| `alpha.md` | [Alpha Doc](./alpha.md) | Link to Guide and use \\| pipe. |", rendered)
        self.assertLess(rendered.index("## Directories"), rendered.index("## Files"))
        self.assertNotIn("zeta.txt", rendered)
        self.assertNotIn("empty-dir", rendered)

    def test_sync_indexes_reports_out_of_date_and_writes_expected_index(self) -> None:
        with tempfile.TemporaryDirectory(prefix="docs-index-", dir=REPO_ROOT) as tmp_name:
            root = Path(tmp_name)
            docs = root / "docs"
            docs.mkdir(parents=True)
            (docs / "README.md").write_text(
                "# Docs\n\n**Purpose:** Docs root.\n\n**Last updated:** 2026-01-01\n",
                encoding="utf-8",
            )
            (docs / "topic.md").write_text(
                "# Topic\n\n**Purpose:** Topic purpose.\n\n**Last updated:** 2026-01-02\n",
                encoding="utf-8",
            )
            (docs / "INDEX.md").write_text("stale\n", encoding="utf-8")
            self._configure_root(root)

            stderr = io.StringIO()
            with redirect_stderr(stderr):
                check_code = self.tool.sync_indexes(check=True)
            write_code = self.tool.sync_indexes(check=False)
            current = (docs / "INDEX.md").read_text(encoding="utf-8")

        self.assertEqual(check_code, 1)
        self.assertIn("Out-of-date generated indexes", stderr.getvalue())
        self.assertEqual(write_code, 0)
        self.assertIn("| `topic.md` | [Topic](./topic.md) | Topic purpose. |", current)

    def test_main_requires_exactly_one_mode(self) -> None:
        with mock.patch.object(sys, "argv", ["docs-index.py"]):
            with redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as raised:
                    self.tool.main()

        self.assertNotEqual(raised.exception.code, 0)

    def test_main_dispatches_check_mode(self) -> None:
        with mock.patch.object(sys, "argv", ["docs-index.py", "--check"]):
            with mock.patch.object(self.tool, "sync_indexes", return_value=3) as sync:
                self.assertEqual(self.tool.main(), 3)

        sync.assert_called_once_with(check=True)


class DocsLifecycleToolTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tool = load_script_module("docs_lifecycle_tool_under_test", "scripts/docs-lifecycle.py")

    def _configure_root(self, root: Path) -> None:
        self.tool.ROOT = root
        self.tool.DOCS = root / "docs"
        self.tool.HISTORY = self.tool.DOCS / "history"
        self.tool.ROLLUPS = self.tool.DOCS / "rollups"
        self.tool.ARCHIVE = self.tool.DOCS / "archive"
        self.tool.ARCHIVE_HISTORY = self.tool.ARCHIVE / "history"
        self.tool.MANIFEST_PATH = self.tool.ARCHIVE / "ARCHIVE-MANIFEST.json"
        self.tool.LEDGER_PATH = self.tool.ARCHIVE / "ARCHIVE-LEDGER.md"

    def test_refresh_creates_manifest_and_ledger_then_validate_passes(self) -> None:
        with tempfile.TemporaryDirectory(prefix="docs-lifecycle-", dir=REPO_ROOT) as tmp_name:
            root = Path(tmp_name)
            self._configure_root(root)
            (root / "docs/rollups").mkdir(parents=True)
            (root / "docs/rollups/CURRENT-STATE.md").write_text("current\n", encoding="utf-8")
            (root / "docs/rollups/NEXT-STAGE-GAP-LEDGER.md").write_text("gaps\n", encoding="utf-8")

            self.assertEqual(self.tool.refresh(), 0)
            stdout = io.StringIO()
            with redirect_stdout(stdout):
                code = self.tool.validate()

            manifest = json.loads(self.tool.MANIFEST_PATH.read_text(encoding="utf-8"))

        self.assertEqual(code, 0)
        self.assertEqual(manifest["version"], 1)
        self.assertIn("docs lifecycle validation passed", stdout.getvalue())

    def test_manifest_and_ledger_reject_non_object_and_non_array_payloads(self) -> None:
        with tempfile.TemporaryDirectory(prefix="docs-lifecycle-", dir=REPO_ROOT) as tmp_name:
            root = Path(tmp_name)
            self._configure_root(root)
            self.tool.MANIFEST_PATH.parent.mkdir(parents=True)
            self.tool.MANIFEST_PATH.write_text("[]", encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "archive manifest must be a JSON object"):
                self.tool.load_manifest()
            with self.assertRaisesRegex(RuntimeError, "archive manifest entries must be a JSON array"):
                self.tool.render_ledger({"entries": "bad"})

    def test_validate_reports_missing_files_bad_entry_type(self) -> None:
        with tempfile.TemporaryDirectory(prefix="docs-lifecycle-", dir=REPO_ROOT) as tmp_name:
            root = Path(tmp_name)
            self._configure_root(root)
            for path in (self.tool.HISTORY, self.tool.ROLLUPS, self.tool.ARCHIVE, self.tool.ARCHIVE_HISTORY):
                path.mkdir(parents=True, exist_ok=True)
            manifest = {
                "version": 1,
                "last_updated": "2026-01-01",
                "archive_root": "docs/archive",
                "rollup_root": "docs/rollups",
                "keep_window": {"history": 1},
                "entries": [
                    {"source_path": "docs/history/a.md", "status": "archived", "archive_path": "docs/archive/history/a.md"},
                    "bad-entry",
                    {"source_path": "missing-status"},
                ],
            }
            self.tool.MANIFEST_PATH.write_text(json.dumps(manifest), encoding="utf-8")
            self.tool.LEDGER_PATH.write_text("stale\n", encoding="utf-8")

            stderr = io.StringIO()
            with redirect_stderr(stderr):
                code = self.tool.validate()

        output = stderr.getvalue()
        self.assertEqual(code, 1)
        self.assertIn("missing lifecycle file: docs/rollups/CURRENT-STATE.md", output)
        self.assertIn("archive manifest entry must be a JSON object", output)

    def test_validate_reports_missing_lifecycle_directories_and_bad_manifest_payload(self) -> None:
        with tempfile.TemporaryDirectory(prefix="docs-lifecycle-", dir=REPO_ROOT) as tmp_name:
            root = Path(tmp_name)
            self._configure_root(root)
            self.tool.MANIFEST_PATH.parent.mkdir(parents=True)
            self.tool.MANIFEST_PATH.write_text('{"entries": "bad"}', encoding="utf-8")

            stderr = io.StringIO()
            with redirect_stderr(stderr):
                code = self.tool.validate()

        output = stderr.getvalue()
        self.assertEqual(code, 1)
        self.assertIn("missing lifecycle directory: docs/history", output)
        self.assertIn("archive manifest entries must be a JSON array", output)

    def test_validate_reports_stale_ledger_missing_keys_and_missing_archive_target(self) -> None:
        with tempfile.TemporaryDirectory(prefix="docs-lifecycle-", dir=REPO_ROOT) as tmp_name:
            root = Path(tmp_name)
            self._configure_root(root)
            for path in (self.tool.HISTORY, self.tool.ROLLUPS, self.tool.ARCHIVE, self.tool.ARCHIVE_HISTORY):
                path.mkdir(parents=True, exist_ok=True)
            (root / "docs/rollups/CURRENT-STATE.md").write_text("current\n", encoding="utf-8")
            (root / "docs/rollups/NEXT-STAGE-GAP-LEDGER.md").write_text("gaps\n", encoding="utf-8")
            manifest = {
                "version": 1,
                "last_updated": "2026-01-01",
                "archive_root": "docs/archive",
                "rollup_root": "docs/rollups",
                "keep_window": {"history": 1},
                "entries": [
                    {"source_path": "docs/history/a.md", "status": "archived", "archive_path": "docs/archive/history/a.md"},
                    {"source_path": "missing-status"},
                ],
            }
            self.tool.MANIFEST_PATH.write_text(json.dumps(manifest), encoding="utf-8")
            self.tool.LEDGER_PATH.write_text("stale\n", encoding="utf-8")

            stderr = io.StringIO()
            with redirect_stderr(stderr):
                code = self.tool.validate()

        output = stderr.getvalue()
        self.assertEqual(code, 1)
        self.assertIn("archive ledger is out of date", output)
        self.assertIn("archive manifest entry #1 is missing `status`", output)
        self.assertIn("archive manifest entry #1 is missing `archive_path`", output)
        self.assertIn("archive manifest target does not exist: docs/archive/history/a.md", output)

    def test_main_dispatches_refresh_and_validate(self) -> None:
        with mock.patch.object(self.tool, "refresh", return_value=3) as refresh:
            with mock.patch.object(sys, "argv", ["docs-lifecycle.py", "refresh"]):
                self.assertEqual(self.tool.main(), 3)
        refresh.assert_called_once_with()

        with mock.patch.object(self.tool, "validate", return_value=4) as validate:
            with mock.patch.object(sys, "argv", ["docs-lifecycle.py", "validate"]):
                self.assertEqual(self.tool.main(), 4)
        validate.assert_called_once_with()


class DocsAuditToolTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tool = load_script_module("docs_audit_tool_under_test", "scripts/docs-audit.py")

    def _configure_root(self, root: Path) -> None:
        self.tool.ROOT = root
        self.tool.DOCS = root / "docs"
        self.tool.REQUIRED_COLLECTION_DIRS = [
            self.tool.DOCS,
            self.tool.DOCS / "history",
            self.tool.DOCS / "archive" / "history",
        ]

    def test_collection_metadata_and_history_name_checks(self) -> None:
        with tempfile.TemporaryDirectory(prefix="docs-audit-", dir=REPO_ROOT) as tmp_name:
            root = Path(tmp_name)
            self._configure_root(root)
            docs = root / "docs"
            history = docs / "history"
            archived = docs / "archive" / "history"
            for directory in (docs, history, archived):
                directory.mkdir(parents=True, exist_ok=True)
                (directory / "README.md").write_text(
                    "# Collection\n\n**Purpose:** Collection docs.\n\n**Last updated:** 2026-01-01\n",
                    encoding="utf-8",
                )
                (directory / "INDEX.md").write_text(
                    "# Index\n\n**Purpose:** Index docs.\n\n**Last updated:** 2026-01-01\n",
                    encoding="utf-8",
                )
            (history / "2026-01-01.md").write_text(
                "# Bad\n\nMissing metadata.\n",
                encoding="utf-8",
            )

            errors = (
                self.tool.check_collections()
                + self.tool.check_metadata()
                + self.tool.check_history_names()
            )

        joined = "\n".join(errors)
        self.assertIn("missing Purpose line: docs/history/2026-01-01.md", joined)
        self.assertIn("missing Last updated line: docs/history/2026-01-01.md", joined)
        self.assertIn("date-only names: docs/history/2026-01-01.md", joined)

    def test_main_can_skip_team_gate_and_reports_subcheck_failures(self) -> None:
        with tempfile.TemporaryDirectory(prefix="docs-audit-", dir=REPO_ROOT) as tmp_name:
            root = Path(tmp_name)
            self._configure_root(root)
            (root / "docs").mkdir(parents=True)
            with mock.patch.dict(self.tool.os.environ, {"STYIO_SKIP_TEAM_DOC_GATE": "1"}, clear=False):
                with mock.patch.object(self.tool, "run_check", side_effect=[["index stale"], []]):
                    stderr = io.StringIO()
                    with redirect_stderr(stderr):
                        code = self.tool.main()

        self.assertEqual(code, 1)
        self.assertIn("docs audit failed", stderr.getvalue())
        self.assertIn("index stale", stderr.getvalue())

    def test_run_check_and_main_include_team_gate_when_not_skipped(self) -> None:
        with mock.patch.object(self.tool.subprocess, "run") as run:
            run.return_value.returncode = 0
            self.assertEqual(self.tool.run_check(["ok"]), [])
            run.return_value.returncode = 1
            run.return_value.stderr = ""
            run.return_value.stdout = ""
            self.assertEqual(self.tool.run_check(["bad"]), ["subprocess failed"])
            run.return_value.stdout = "stdout failure"
            self.assertEqual(self.tool.run_check(["bad"]), ["stdout failure"])
            run.return_value.stderr = "stderr failure"
            self.assertEqual(self.tool.run_check(["bad"]), ["stderr failure"])

        with tempfile.TemporaryDirectory(prefix="docs-audit-", dir=REPO_ROOT) as tmp_name:
            root = Path(tmp_name)
            self._configure_root(root)
            for directory in self.tool.REQUIRED_COLLECTION_DIRS:
                directory.mkdir(parents=True, exist_ok=True)
                (directory / "README.md").write_text(
                    "# Collection\n\n**Purpose:** Collection docs.\n\n**Last updated:** 2026-01-01\n",
                    encoding="utf-8",
                )
                (directory / "INDEX.md").write_text(
                    "# Index\n\n**Purpose:** Index docs.\n\n**Last updated:** 2026-01-01\n",
                    encoding="utf-8",
                )
            with mock.patch.dict(self.tool.os.environ, {}, clear=True):
                with mock.patch.object(self.tool, "run_check", return_value=[]) as run_check:
                    stdout = io.StringIO()
                    with redirect_stdout(stdout):
                        code = self.tool.main()

        self.assertEqual(code, 0)
        self.assertIn("docs audit passed", stdout.getvalue())
        self.assertEqual(run_check.call_count, 3)

    def test_main_passes_when_all_checks_are_clean(self) -> None:
        with tempfile.TemporaryDirectory(prefix="docs-audit-", dir=REPO_ROOT) as tmp_name:
            root = Path(tmp_name)
            self._configure_root(root)
            for directory in self.tool.REQUIRED_COLLECTION_DIRS:
                directory.mkdir(parents=True, exist_ok=True)
                (directory / "README.md").write_text(
                    "# Collection\n\n**Purpose:** Collection docs.\n\n**Last updated:** 2026-01-01\n",
                    encoding="utf-8",
                )
                (directory / "INDEX.md").write_text(
                    "# Index\n\n**Purpose:** Index docs.\n\n**Last updated:** 2026-01-01\n",
                    encoding="utf-8",
                )
            with mock.patch.dict(self.tool.os.environ, {"STYIO_SKIP_TEAM_DOC_GATE": "1"}, clear=False):
                with mock.patch.object(self.tool, "run_check", return_value=[]):
                    stdout = io.StringIO()
                    with redirect_stdout(stdout):
                        code = self.tool.main()

        self.assertEqual(code, 0)
        self.assertIn("docs audit passed", stdout.getvalue())


class TeamDocsGateToolTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tool = load_script_module("team_docs_gate_tool_under_test", "scripts/team-docs-gate.py")

    def test_path_parsing_prefix_matching_and_required_updates(self) -> None:
        with mock.patch.object(self.tool.subprocess, "run") as run:
            run.return_value = mock.Mock(returncode=0, stdout="ok\n", stderr="")
            self.assertIs(self.tool.run_git(["status", "--short"]), run.return_value)
        run.assert_called_once_with(
            ["git", "status", "--short"],
            cwd=self.tool.ROOT,
            text=True,
            capture_output=True,
        )

        parsed = self.tool.parse_name_status(
            "M\tREADME.md\n"
            "R100\told.md\tdocs/contracts/New.md\n"
            "C100\told.dart\tfrontend/vityo_app/lib/src/backend_toolchain/adapter.dart\n"
            "\n"
        )

        required = self.tool.required_team_updates(parsed)

        self.assertEqual(
            [path.as_posix() for path in parsed],
            [
                "README.md",
                "docs/contracts/New.md",
                "frontend/vityo_app/lib/src/backend_toolchain/adapter.dart",
            ],
        )
        labels = {rule.label for rule in required}
        self.assertIn("Adapter / Contracts", labels)
        self.assertIn("Docs / Delivery", labels)
        self.assertTrue(self.tool.matches_prefix(Path("docs/contracts/New.md"), "docs/contracts/"))
        self.assertTrue(self.tool.is_generated_index(Path("docs/contracts/INDEX.md")))
        self.assertTrue(self.tool.is_ignored_trigger(Path("docs/contracts/INDEX.md")))
        self.assertTrue(self.tool.is_ignored_trigger(Path("docs/teams/SHELL-EDITOR-RUNBOOK.md")))
        self.assertIn("... 1 more", self.tool.format_paths([Path(str(index)) for index in range(10)], limit=9))

    def test_changed_path_collectors_parse_git_output_and_raise_errors(self) -> None:
        with mock.patch.object(self.tool, "run_git") as run_git:
            run_git.return_value = mock.Mock(
                returncode=0,
                stdout="\n M docs/a.md\nR  old.md -> docs/b.md\n?? docs/c.md\n",
                stderr="",
            )
            self.assertEqual(
                [path.as_posix() for path in self.tool.changed_from_worktree()],
                ["docs/a.md", "docs/b.md", "docs/c.md"],
            )

            run_git.return_value = mock.Mock(returncode=1, stdout="", stderr="bad status")
            with self.assertRaisesRegex(RuntimeError, "bad status"):
                self.tool.changed_from_worktree()

            run_git.return_value = mock.Mock(returncode=0, stdout="M\tdocs/a.md\n", stderr="")
            self.assertEqual(self.tool.changed_from_staged(), [Path("docs/a.md")])

            run_git.return_value = mock.Mock(returncode=1, stdout="", stderr="bad staged")
            with self.assertRaisesRegex(RuntimeError, "bad staged"):
                self.tool.changed_from_staged()

            run_git.side_effect = [
                mock.Mock(returncode=0, stdout="abc123\n", stderr=""),
                mock.Mock(returncode=0, stdout="M\tdocs/base.md\n", stderr=""),
            ]
            self.assertEqual(self.tool.changed_from_base("origin/main"), [Path("docs/base.md")])

            run_git.side_effect = [
                mock.Mock(returncode=1, stdout="", stderr="bad merge-base"),
            ]
            with self.assertRaisesRegex(RuntimeError, "bad merge-base"):
                self.tool.changed_from_base("origin/main")

            run_git.side_effect = [
                mock.Mock(returncode=0, stdout="abc123\n", stderr=""),
                mock.Mock(returncode=1, stdout="", stderr="bad diff"),
            ]
            with self.assertRaisesRegex(RuntimeError, "bad diff"):
                self.tool.changed_from_base("origin/main")

    def test_validate_runbook_format_accepts_template_and_rejects_order_and_extra_headings(self) -> None:
        with tempfile.TemporaryDirectory(prefix="team-docs-", dir=REPO_ROOT) as tmp_name:
            root = Path(tmp_name)
            original_root = self.tool.ROOT
            self.tool.ROOT = root
            try:
                runbook = Path("docs/teams/SHELL-EDITOR-RUNBOOK.md")
                absolute = root / runbook
                absolute.parent.mkdir(parents=True)
                headings = "\n\n".join(f"## {heading}\nBody." for heading in self.tool.TEAM_REQUIRED_HEADINGS)
                absolute.write_text(
                    "# Shell Editor Runbook\n\n"
                    "**Purpose:** Own editor work.\n\n"
                    "**Last updated:** 2026-01-01\n\n"
                    f"{headings}\n",
                    encoding="utf-8",
                )
                self.assertEqual(self.tool.validate_runbook_format(runbook, self.tool.TEAM_REQUIRED_HEADINGS), [])

                absolute.write_text(
                    "# Shell Editor Notes\n\n"
                    "**Purpose:** Own editor work.\n\n"
                    "**Last updated:** 2026-01-01\n\n"
                    "## Daily Workflow\nBody.\n\n"
                    "## Mission\nBody.\n\n"
                    "## Extra\nBody.\n",
                    encoding="utf-8",
                )
                errors = self.tool.validate_runbook_format(runbook, self.tool.TEAM_REQUIRED_HEADINGS)
            finally:
                self.tool.ROOT = original_root

        joined = "\n".join(errors)
        self.assertIn("must start with an H1 ending in 'Runbook'", joined)
        self.assertIn("missing required heading: ## Owned Surface", joined)
        self.assertIn("has non-template H2 heading: ## Extra", joined)

    def test_validate_runbook_format_reports_missing_file_metadata_duplicate_and_order(self) -> None:
        with tempfile.TemporaryDirectory(prefix="team-docs-", dir=REPO_ROOT) as tmp_name:
            root = Path(tmp_name)
            original_root = self.tool.ROOT
            self.tool.ROOT = root
            try:
                runbook = Path("docs/teams/RUNTIME-AGENT-RUNBOOK.md")
                self.assertEqual(
                    self.tool.validate_runbook_format(runbook, self.tool.TEAM_REQUIRED_HEADINGS),
                    ["docs/teams/RUNTIME-AGENT-RUNBOOK.md is missing"],
                )

                absolute = root / runbook
                absolute.parent.mkdir(parents=True)
                duplicate_headings = "\n\n".join(
                    ["## Mission\nBody.", "## Mission\nAgain."]
                    + [f"## {heading}\nBody." for heading in self.tool.TEAM_REQUIRED_HEADINGS[1:]]
                )
                absolute.write_text("# Runtime Agent Runbook\n\n" f"{duplicate_headings}\n", encoding="utf-8")
                metadata_errors = self.tool.validate_runbook_format(runbook, self.tool.TEAM_REQUIRED_HEADINGS)

                ordered = ["Owned Surface", "Mission", *self.tool.TEAM_REQUIRED_HEADINGS[2:]]
                absolute.write_text(
                    "# Runtime Agent Runbook\n\n"
                    "**Purpose:** Runtime work.\n\n"
                    "**Last updated:** 2026-01-01\n\n"
                    + "\n\n".join(f"## {heading}\nBody." for heading in ordered)
                    + "\n",
                    encoding="utf-8",
                )
                order_errors = self.tool.validate_runbook_format(runbook, self.tool.TEAM_REQUIRED_HEADINGS)
            finally:
                self.tool.ROOT = original_root

        joined = "\n".join(metadata_errors)
        self.assertIn("missing top-level '**Purpose:** ...' metadata", joined)
        self.assertIn("missing top-level '**Last updated:** YYYY-MM-DD' metadata", joined)
        self.assertIn("has duplicate heading: ## Mission", joined)
        self.assertIn("H2 headings must follow template order", "\n".join(order_errors))

    def test_validate_all_runbook_formats_uses_coordination_template(self) -> None:
        with tempfile.TemporaryDirectory(prefix="team-docs-", dir=REPO_ROOT) as tmp_name:
            root = Path(tmp_name)
            original_root = self.tool.ROOT
            original_runbooks = self.tool.TEAM_RUNBOOKS
            self.tool.ROOT = root
            self.tool.TEAM_RUNBOOKS = {
                Path("docs/teams/COORDINATION-RUNBOOK.md"),
                Path("docs/teams/SHELL-EDITOR-RUNBOOK.md"),
            }
            try:
                for path, headings in (
                    (Path("docs/teams/COORDINATION-RUNBOOK.md"), self.tool.COORDINATION_REQUIRED_HEADINGS),
                    (Path("docs/teams/SHELL-EDITOR-RUNBOOK.md"), self.tool.TEAM_REQUIRED_HEADINGS),
                ):
                    absolute = root / path
                    absolute.parent.mkdir(parents=True, exist_ok=True)
                    absolute.write_text(
                        f"# {path.stem.title()} Runbook\n\n"
                        "**Purpose:** Test runbook.\n\n"
                        "**Last updated:** 2026-01-01\n\n"
                        + "\n\n".join(f"## {heading}\nBody." for heading in headings)
                        + "\n",
                        encoding="utf-8",
                    )

                errors = self.tool.validate_all_runbook_formats()
            finally:
                self.tool.ROOT = original_root
                self.tool.TEAM_RUNBOOKS = original_runbooks

        self.assertEqual(errors, [])

    def test_run_gate_reports_missing_runbook_and_stats_then_verbose_success(self) -> None:
        changed = [
            Path("frontend/vityo_app/lib/src/backend_toolchain/adapter.dart"),
            Path("docs/teams/ADAPTER-CONTRACTS-RUNBOOK.md"),
        ]
        with mock.patch.object(self.tool, "validate_all_runbook_formats", return_value=[]):
            stderr = io.StringIO()
            with redirect_stderr(stderr):
                failed = self.tool.run_gate(changed, verbose=False)
            stdout = io.StringIO()
            with redirect_stdout(stdout):
                passed = self.tool.run_gate(
                    [
                        Path("frontend/vityo_app/lib/src/backend_toolchain/adapter.dart"),
                        Path("docs/teams/ADAPTER-CONTRACTS-RUNBOOK.md"),
                        Path("docs/teams/DOC-STATS.md"),
                    ],
                    verbose=True,
                )

        self.assertEqual(failed, 1)
        self.assertIn("Team runbook changes require refreshing docs/teams/DOC-STATS.md", stderr.getvalue())
        self.assertEqual(passed, 0)
        self.assertIn("team docs gate passed", stdout.getvalue())
        self.assertIn("changed paths:", stdout.getvalue())

        with mock.patch.object(self.tool, "validate_all_runbook_formats", return_value=[]):
            stdout = io.StringIO()
            with redirect_stdout(stdout):
                quiet = self.tool.run_gate([], verbose=False)

        self.assertEqual(quiet, 0)
        self.assertIn("team docs gate passed", stdout.getvalue())
        self.assertNotIn("changed paths:", stdout.getvalue())

    def test_run_gate_reports_format_errors_and_missing_required_runbook(self) -> None:
        with mock.patch.object(self.tool, "validate_all_runbook_formats", return_value=["bad runbook"]):
            stderr = io.StringIO()
            with redirect_stderr(stderr):
                code = self.tool.run_gate(
                    [Path("frontend/vityo_app/lib/src/backend_toolchain/adapter.dart")],
                    verbose=False,
                )

        output = stderr.getvalue()
        self.assertEqual(code, 1)
        self.assertIn("Runbook format validation failed", output)
        self.assertIn("Adapter / Contracts changed files require updating", output)

    def test_main_uses_base_and_staged_modes(self) -> None:
        with mock.patch.object(self.tool, "run_gate", return_value=0) as run_gate:
            with mock.patch.object(self.tool, "changed_from_base", return_value=[Path("docs/a.md")]) as changed:
                with mock.patch.object(sys, "argv", ["team-docs-gate.py", "--base", "origin/main", "--verbose"]):
                    self.assertEqual(self.tool.main(), 0)
        changed.assert_called_once_with("origin/main")
        run_gate.assert_called_once_with([Path("docs/a.md")], True)

        with mock.patch.object(self.tool, "run_gate", return_value=0) as run_gate:
            with mock.patch.object(self.tool, "changed_from_staged", return_value=[Path("docs/b.md")]) as changed:
                with mock.patch.object(sys, "argv", ["team-docs-gate.py", "--mode", "staged"]):
                    self.assertEqual(self.tool.main(), 0)
        changed.assert_called_once_with()
        run_gate.assert_called_once_with([Path("docs/b.md")], False)

    def test_main_returns_error_when_changed_path_collection_raises(self) -> None:
        with mock.patch.object(sys, "argv", ["team-docs-gate.py"]):
            with mock.patch.object(self.tool, "changed_from_worktree", side_effect=RuntimeError("git failed")):
                stderr = io.StringIO()
                with redirect_stderr(stderr):
                    code = self.tool.main()

        self.assertEqual(code, 2)
        self.assertIn("team docs gate error: git failed", stderr.getvalue())


class FacadeGateToolTest(unittest.TestCase):
    def test_ecosystem_facades_emit_json_skip_when_canonical_gate_is_absent(self) -> None:
        for name, relative_path in (
            ("ecosystem_product_gate_under_test", "scripts/ecosystem-product-gate.py"),
            ("ecosystem_sample_workflow_gate_under_test", "scripts/ecosystem-sample-workflow-gate.py"),
        ):
            tool = load_script_module(name, relative_path)
            with tempfile.TemporaryDirectory(prefix="facade-gate-", dir=REPO_ROOT) as tmp_name:
                tool.CANONICAL_GATE = Path(tmp_name) / "missing.py"
                stdout = io.StringIO()
                with redirect_stdout(stdout):
                    code = tool.main(["--json"])

            payload = json.loads(stdout.getvalue())
            self.assertEqual(code, 0)
            self.assertTrue(payload["ok"])
            self.assertTrue(payload["skipped"])

    def test_ecosystem_facades_emit_text_skip_when_canonical_gate_is_absent(self) -> None:
        for name, relative_path in (
            ("ecosystem_product_gate_text_skip_under_test", "scripts/ecosystem-product-gate.py"),
            ("ecosystem_sample_workflow_gate_text_skip_under_test", "scripts/ecosystem-sample-workflow-gate.py"),
        ):
            tool = load_script_module(name, relative_path)
            with tempfile.TemporaryDirectory(prefix="facade-gate-", dir=REPO_ROOT) as tmp_name:
                tool.CANONICAL_GATE = Path(tmp_name) / "missing.py"
                stdout = io.StringIO()
                with redirect_stdout(stdout):
                    code = tool.main([])

            self.assertEqual(code, 0)
            self.assertIn("[SKIP] canonical gate not found", stdout.getvalue())

    def test_ecosystem_facades_delegate_to_canonical_gate(self) -> None:
        facades = (
            ("ecosystem_product_gate_delegate_under_test", "scripts/ecosystem-product-gate.py"),
            (
                "ecosystem_sample_workflow_gate_delegate_under_test",
                "scripts/ecosystem-sample-workflow-gate.py",
            ),
        )
        for name, relative_path in facades:
            tool = load_script_module(name, relative_path)
            with tempfile.TemporaryDirectory(prefix="facade-gate-", dir=REPO_ROOT) as tmp_name:
                gate = Path(tmp_name) / "gate.py"
                gate.write_text("import sys\nraise SystemExit(7)\n", encoding="utf-8")
                tool.CANONICAL_GATE = gate
                with mock.patch.object(tool.subprocess, "run") as run:
                    run.return_value.returncode = 7
                    code = tool.main(["--json"])

            self.assertEqual(code, 7)
            command = run.call_args.args[0]
            self.assertEqual(command[:2], [sys.executable, str(gate)])
            self.assertEqual(command[2:], ["--json"])
            self.assertEqual(run.call_args.kwargs["cwd"], tool.ROOT.parent)

    def test_ecosystem_product_facade_delegates_to_canonical_gate(self) -> None:
        tool = load_script_module(
            "ecosystem_product_gate_delegate_legacy_under_test",
            "scripts/ecosystem-product-gate.py",
        )
        with tempfile.TemporaryDirectory(prefix="facade-gate-", dir=REPO_ROOT) as tmp_name:
            gate = Path(tmp_name) / "gate.py"
            gate.write_text("import sys\nraise SystemExit(7)\n", encoding="utf-8")
            tool.CANONICAL_GATE = gate
            with mock.patch.object(tool.subprocess, "run") as run:
                run.return_value.returncode = 7
                code = tool.main(["--json"])

        self.assertEqual(code, 7)
        run.assert_called_once()

    def test_check_repo_hygiene_delegates_to_canonical_gate(self) -> None:
        tool = load_script_module("check_repo_hygiene_under_test", "scripts/check_repo_hygiene.py")
        with mock.patch.object(tool.subprocess, "run") as run:
            run.return_value.returncode = 3
            code = tool.main()

        self.assertEqual(code, 3)
        command = run.call_args.args[0]
        self.assertEqual(command[-1], "tracked")


if __name__ == "__main__":
    unittest.main()
