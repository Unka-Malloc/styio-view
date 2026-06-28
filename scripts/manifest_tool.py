#!/usr/bin/env python3
"""Validate Better Plan manifests and generate task IDs."""

from __future__ import annotations

import argparse
import json
import re
import sys
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any


MANIFEST_NAME = "Manifest.json"
CHECKPOINTS_NAME = "Checkpoints.json"
STATE_FILE_NAMES = {MANIFEST_NAME, CHECKPOINTS_NAME}
VALID_STATUSES = {"pending", "in_progress", "completed", "blocked", "skipped"}
VALID_DIFFICULTIES = {"low", "medium", "high", "deep"}
VALID_PLATFORMS = {"linux", "macos", "windows"}
UUID4_PATTERN = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
PLAN_REQUIRED_FIELDS = {
    "id",
    "status",
    "title",
    "directory",
    "source_files",
    "goal",
    "description",
    "checkpoints",
}
TASK_REQUIRED_FIELDS = {
    "id",
    "status",
    "prerequisites",
    "platform",
    "difficulty",
    "goal",
    "description",
    "acceptance_criteria",
    "commit",
    "next",
}
@dataclass(frozen=True)
class Issue:
    path: Path
    message: str


@dataclass(frozen=True)
class WorkflowStateMachine:
    statuses: frozenset[str]
    transitions: dict[str, frozenset[str]]
    terminal_statuses: frozenset[str]

    def is_status(self, value: Any) -> bool:
        return isinstance(value, str) and value in self.statuses

    def can_transition(self, current: str, target: str) -> bool:
        return target in self.transitions.get(current, frozenset())

    def status_issue(self, path: Path, prefix: str, value: Any) -> Issue | None:
        if self.is_status(value):
            return None
        values = ", ".join(sorted(self.statuses))
        return Issue(path, f"{prefix}.status: must be one of {values}")

    def transition_issues(self, path: Path, prefix: str, current: Any, target: Any) -> list[Issue]:
        issues: list[Issue] = []
        current_issue = self.status_issue(path, f"{prefix}.from", current)
        if current_issue is not None:
            issues.append(current_issue)
        target_issue = self.status_issue(path, f"{prefix}.to", target)
        if target_issue is not None:
            issues.append(target_issue)
        if issues:
            return issues

        if not self.can_transition(str(current), str(target)):
            allowed = ", ".join(sorted(self.transitions[str(current)]))
            issues.append(Issue(path, f"{prefix}: cannot transition from {current!r} to {target!r}; allowed targets: {allowed}"))
        return issues

    def checkpoint_snapshot_issues(self, path: Path, data: list[Any]) -> list[Issue]:
        issues: list[Issue] = []
        node_statuses: dict[str, str] = {}
        in_progress_indexes: list[int] = []

        for index, node in enumerate(data):
            if not isinstance(node, dict):
                continue
            node_id = node.get("id")
            status = node.get("status")
            if isinstance(node_id, str) and self.is_status(status):
                node_statuses[node_id] = status
            if status == "in_progress":
                in_progress_indexes.append(index)

        if len(in_progress_indexes) > 1:
            indexes = ", ".join(f"node[{index}]" for index in in_progress_indexes)
            issues.append(Issue(path, f"state machine: only one node may be in_progress at a time: {indexes}"))

        for index, node in enumerate(data):
            if not isinstance(node, dict):
                continue

            status = node.get("status")
            if not self.is_status(status):
                continue

            prerequisites = node.get("prerequisites")
            if status in {"in_progress", "completed"} and is_string_list(prerequisites):
                incomplete = [ref for ref in prerequisites if node_statuses.get(ref) != "completed"]
                if incomplete:
                    refs = ", ".join(repr(ref) for ref in incomplete)
                    issues.append(Issue(path, f"node[{index}].status: cannot be {status!r} until prerequisites are completed: {refs}"))

            acceptance_criteria = node.get("acceptance_criteria")
            if status == "completed" and isinstance(acceptance_criteria, list):
                unchecked = [
                    criterion_index
                    for criterion_index, criterion in enumerate(acceptance_criteria)
                    if isinstance(criterion, dict) and criterion.get("checked") is False
                ]
                if unchecked:
                    indexes = ", ".join(str(criterion_index) for criterion_index in unchecked)
                    issues.append(Issue(path, f"node[{index}].status: cannot be 'completed' with unchecked acceptance criteria: {indexes}"))

        return issues

    def plan_snapshot_issues(self, path: Path, data: list[Any]) -> list[Issue]:
        issues: list[Issue] = []

        for index, plan in enumerate(data):
            if not isinstance(plan, dict):
                continue
            status = plan.get("status")
            checkpoints = plan.get("checkpoints")
            if not self.is_status(status) or not is_relative_workspace_path(checkpoints):
                continue

            checkpoint_path = path.parent / normalize_workspace_path(str(checkpoints))
            try:
                checkpoint_data = json.loads(checkpoint_path.read_text(encoding="utf-8"))
            except (json.JSONDecodeError, OSError):
                continue
            if not isinstance(checkpoint_data, list):
                continue

            node_statuses = [
                node.get("status")
                for node in checkpoint_data
                if isinstance(node, dict) and self.is_status(node.get("status"))
            ]
            if not node_statuses:
                continue

            if status == "completed":
                unfinished = sorted(set(node_statuses) - self.terminal_statuses)
                if unfinished:
                    values = ", ".join(unfinished)
                    issues.append(Issue(path, f"plan[{index}].status: cannot be 'completed' while checkpoints contain non-terminal nodes: {values}"))
            elif status == "blocked" and "blocked" not in node_statuses:
                issues.append(Issue(path, f"plan[{index}].status: cannot be 'blocked' without a blocked checkpoint node"))
            elif status == "skipped" and "in_progress" in node_statuses:
                issues.append(Issue(path, f"plan[{index}].status: cannot be 'skipped' while a checkpoint node is in_progress"))

        return issues


WORKFLOW_STATE_MACHINE = WorkflowStateMachine(
    statuses=frozenset(VALID_STATUSES),
    transitions={
        "pending": frozenset({"pending", "in_progress", "blocked", "skipped"}),
        "in_progress": frozenset({"in_progress", "completed", "blocked", "skipped"}),
        "blocked": frozenset({"blocked", "in_progress", "skipped"}),
        "completed": frozenset({"completed"}),
        "skipped": frozenset({"skipped"}),
    },
    terminal_statuses=frozenset({"completed", "skipped"}),
)


def generate_id() -> str:
    return str(uuid.uuid4())


def find_manifests(root: Path) -> list[Path]:
    if root.is_file():
        return [root] if root.name in STATE_FILE_NAMES else []

    manifest = root / MANIFEST_NAME
    return [manifest] if manifest.is_file() else []


def referenced_checkpoints_files(manifest: Path) -> list[Path]:
    try:
        data = json.loads(manifest.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return []

    if not isinstance(data, list):
        return []

    checkpoints: list[Path] = []
    seen: set[Path] = set()
    for plan in data:
        if not isinstance(plan, dict):
            continue
        value = plan.get("checkpoints")
        if not is_relative_workspace_path(value):
            continue
        path = manifest.parent / normalize_workspace_path(value)
        if path.name != CHECKPOINTS_NAME or not path.is_file() or path in seen:
            continue
        seen.add(path)
        checkpoints.append(path)
    return checkpoints


def is_string_list(value: Any) -> bool:
    return isinstance(value, list) and all(isinstance(item, str) for item in value)


def is_manifest_id(value: Any) -> bool:
    return isinstance(value, str) and UUID4_PATTERN.fullmatch(value) is not None


def is_git_entry_path(value: Any) -> bool:
    if not isinstance(value, str) or not value.strip():
        return False
    normalized = value.strip().replace("\\", "/").rstrip("/")
    return normalized.split("/")[-1] == ".git"


def is_relative_workspace_path(value: Any) -> bool:
    if not isinstance(value, str) or not value.strip():
        return False
    normalized = value.strip().replace("\\", "/")
    if normalized.startswith("/") or re.match(r"^[A-Za-z]:/", normalized):
        return False
    parts = [part for part in normalized.split("/") if part]
    return bool(parts) and all(part not in {".", ".."} for part in parts)


def normalize_workspace_path(value: str) -> str:
    normalized = value.strip().replace("\\", "/")
    return "/".join(part for part in normalized.split("/") if part)


def expected_checkpoints_path(directory: str) -> str:
    return f"{normalize_workspace_path(directory)}/{CHECKPOINTS_NAME}"


def is_workspace_root_manifest(path: Path) -> bool:
    return path.name == MANIFEST_NAME


def validate_manifest(path: Path) -> tuple[int, list[Issue]]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        return 0, [Issue(path, f"invalid JSON at line {exc.lineno}, column {exc.colno}: {exc.msg}")]
    except OSError as exc:
        return 0, [Issue(path, f"cannot read file: {exc}")]

    if not isinstance(data, list):
        return 0, [Issue(path, "top-level value must be an array")]

    if path.name == MANIFEST_NAME:
        return validate_plan_manifest_data(path, data)
    if path.name == CHECKPOINTS_NAME:
        return validate_checkpoints_data(path, data)
    return len(data), [Issue(path, f"state file must be named {MANIFEST_NAME} or {CHECKPOINTS_NAME}")]


def validate_plan_manifest_data(path: Path, data: list[Any]) -> tuple[int, list[Issue]]:
    issues: list[Issue] = []
    seen: set[str] = set()
    directories: set[str] = set()

    if not is_workspace_root_manifest(path):
        issues.append(Issue(path, f"Plan manifest must be named {MANIFEST_NAME}"))

    for index, plan in enumerate(data):
        prefix = f"plan[{index}]"
        if not isinstance(plan, dict):
            issues.append(Issue(path, f"{prefix}: must be an object"))
            continue

        missing = sorted(PLAN_REQUIRED_FIELDS - set(plan))
        for field in missing:
            issues.append(Issue(path, f"{prefix}.{field}: missing required field"))

        extra = sorted(set(plan) - PLAN_REQUIRED_FIELDS)
        for field in extra:
            issues.append(Issue(path, f"{prefix}.{field}: unknown field"))

        plan_id = plan.get("id")
        if not isinstance(plan_id, str) or not plan_id.strip():
            issues.append(Issue(path, f"{prefix}.id: must be a non-empty string"))
        else:
            if not is_manifest_id(plan_id):
                issues.append(Issue(path, f"{prefix}.id: must be generated by this skill's uuid command"))
            if plan_id in seen:
                issues.append(Issue(path, f"{prefix}.id: duplicate id {plan_id!r}"))
            else:
                seen.add(plan_id)

        status_issue = WORKFLOW_STATE_MACHINE.status_issue(path, prefix, plan.get("status"))
        if status_issue is not None:
            issues.append(status_issue)

        for field in ("title", "goal", "description"):
            if not isinstance(plan.get(field), str) or not plan.get(field, "").strip():
                issues.append(Issue(path, f"{prefix}.{field}: must be a non-empty string"))

        directory = plan.get("directory")
        normalized_directory = ""
        if not is_relative_workspace_path(directory):
            issues.append(Issue(path, f"{prefix}.directory: must be a relative workspace path"))
        else:
            normalized_directory = str(directory).strip().replace("\\", "/").strip("/")
            if normalized_directory in directories:
                issues.append(Issue(path, f"{prefix}.directory: duplicate directory {normalized_directory!r}"))
            else:
                directories.add(normalized_directory)
            plan_dir = path.parent / normalized_directory
            if not plan_dir.is_dir():
                issues.append(Issue(path, f"{prefix}.directory: directory does not exist: {normalized_directory}"))

        source_files = plan.get("source_files")
        if not is_string_list(source_files):
            issues.append(Issue(path, f"{prefix}.source_files: must be an array of strings"))
        elif any(not item.strip() for item in source_files):
            issues.append(Issue(path, f"{prefix}.source_files: must not contain empty strings"))

        checkpoints = plan.get("checkpoints")
        if not is_relative_workspace_path(checkpoints):
            issues.append(Issue(path, f"{prefix}.checkpoints: must be a relative path to {CHECKPOINTS_NAME}"))
        elif normalized_directory:
            normalized_checkpoints = str(checkpoints).strip().replace("\\", "/").strip("/")
            expected = expected_checkpoints_path(normalized_directory)
            if normalized_checkpoints != expected:
                issues.append(Issue(path, f"{prefix}.checkpoints: must be {expected!r}"))
            if not (path.parent / normalized_checkpoints).is_file():
                issues.append(Issue(path, f"{prefix}.checkpoints: file does not exist: {normalized_checkpoints}"))

    issues.extend(WORKFLOW_STATE_MACHINE.plan_snapshot_issues(path, data))
    return len(data), issues


def validate_checkpoints_data(path: Path, data: list[Any]) -> tuple[int, list[Issue]]:
    issues: list[Issue] = []
    seen: set[str] = set()

    for index, node in enumerate(data):
        prefix = f"node[{index}]"
        if not isinstance(node, dict):
            issues.append(Issue(path, f"{prefix}: must be an object"))
            continue

        missing = sorted(TASK_REQUIRED_FIELDS - set(node))
        for field in missing:
            issues.append(Issue(path, f"{prefix}.{field}: missing required field"))

        extra = sorted(set(node) - TASK_REQUIRED_FIELDS)
        for field in extra:
            issues.append(Issue(path, f"{prefix}.{field}: unknown field"))

        node_id = node.get("id")
        if not isinstance(node_id, str) or not node_id.strip():
            issues.append(Issue(path, f"{prefix}.id: must be a non-empty string"))
        else:
            if not is_manifest_id(node_id):
                issues.append(Issue(path, f"{prefix}.id: must be generated by this skill's uuid command"))
            if node_id in seen:
                issues.append(Issue(path, f"{prefix}.id: duplicate id {node_id!r}"))
            else:
                seen.add(node_id)

        status_issue = WORKFLOW_STATE_MACHINE.status_issue(path, prefix, node.get("status"))
        if status_issue is not None:
            issues.append(status_issue)

        difficulty = node.get("difficulty")
        if difficulty not in VALID_DIFFICULTIES:
            values = ", ".join(sorted(VALID_DIFFICULTIES))
            issues.append(Issue(path, f"{prefix}.difficulty: must be one of {values}"))

        for field in ("prerequisites", "next"):
            if not is_string_list(node.get(field)):
                issues.append(Issue(path, f"{prefix}.{field}: must be an array of strings"))

        acceptance_criteria = node.get("acceptance_criteria")
        if not isinstance(acceptance_criteria, list):
            issues.append(Issue(path, f"{prefix}.acceptance_criteria: must be a non-empty array of checkbox objects"))
        elif not acceptance_criteria:
            issues.append(Issue(path, f"{prefix}.acceptance_criteria: must not be empty"))
        else:
            for criterion_index, criterion in enumerate(acceptance_criteria):
                criterion_prefix = f"{prefix}.acceptance_criteria[{criterion_index}]"
                if not isinstance(criterion, dict):
                    issues.append(Issue(path, f"{criterion_prefix}: must be an object"))
                    continue
                missing_criterion_fields = sorted({"checked", "text"} - set(criterion))
                for field in missing_criterion_fields:
                    issues.append(Issue(path, f"{criterion_prefix}.{field}: missing required field"))
                extra_criterion_fields = sorted(set(criterion) - {"checked", "text"})
                for field in extra_criterion_fields:
                    issues.append(Issue(path, f"{criterion_prefix}.{field}: unknown field"))
                if type(criterion.get("checked")) is not bool:
                    issues.append(Issue(path, f"{criterion_prefix}.checked: must be a boolean"))
                if not isinstance(criterion.get("text"), str) or not criterion.get("text", "").strip():
                    issues.append(Issue(path, f"{criterion_prefix}.text: must be a non-empty string"))

        platform = node.get("platform")
        if platform not in VALID_PLATFORMS:
            values = ", ".join(sorted(VALID_PLATFORMS))
            issues.append(Issue(path, f"{prefix}.platform: must be one of {values}"))

        for field in ("goal", "description"):
            if not isinstance(node.get(field), str) or not node.get(field, "").strip():
                issues.append(Issue(path, f"{prefix}.{field}: must be a non-empty string"))

        commit = node.get("commit")
        if not isinstance(commit, dict):
            issues.append(Issue(path, f"{prefix}.commit: must be an object"))
        else:
            for field in ("repository", "message", "target"):
                value = commit.get(field)
                if not isinstance(value, str) or not value.strip():
                    issues.append(Issue(path, f"{prefix}.commit.{field}: must be a non-empty string"))
            if not is_git_entry_path(commit.get("repository")):
                issues.append(Issue(path, f"{prefix}.commit.repository: must point to a .git filesystem entry"))
            extra_commit_fields = sorted(set(commit) - {"repository", "message", "target"})
            for field in extra_commit_fields:
                issues.append(Issue(path, f"{prefix}.commit.{field}: unknown field"))

    id_first_index: dict[str, int] = {}
    for index, node in enumerate(data):
        if isinstance(node, dict) and isinstance(node.get("id"), str):
            id_first_index.setdefault(node["id"], index)

    for index, node in enumerate(data):
        if not isinstance(node, dict):
            continue

        prerequisites = node.get("prerequisites")
        if isinstance(prerequisites, list):
            for ref in prerequisites:
                if not isinstance(ref, str):
                    continue
                ref_index = id_first_index.get(ref)
                if ref_index is None:
                    issues.append(Issue(path, f"node[{index}].prerequisites: unknown node id {ref!r}"))
                elif ref_index >= index:
                    issues.append(Issue(path, f"node[{index}].prerequisites: must reference an earlier node id {ref!r}"))

        next_refs = node.get("next")
        if isinstance(next_refs, list):
            for ref in next_refs:
                if not isinstance(ref, str):
                    continue
                if not is_manifest_id(ref):
                    issues.append(Issue(path, f"node[{index}].next: must contain UUIDs generated by this skill's uuid command"))
                elif ref not in id_first_index:
                    issues.append(Issue(path, f"node[{index}].next: unknown node id {ref!r}"))

    issues.extend(validate_prerequisite_cycles(path, data))
    issues.extend(WORKFLOW_STATE_MACHINE.checkpoint_snapshot_issues(path, data))
    return len(data), issues


def validate_prerequisite_cycles(path: Path, data: Any) -> list[Issue]:
    if not isinstance(data, list):
        return []

    graph: dict[str, list[str]] = {}
    for node in data:
        if not isinstance(node, dict):
            continue
        node_id = node.get("id")
        prereqs = node.get("prerequisites")
        if isinstance(node_id, str) and is_string_list(prereqs):
            graph[node_id] = list(prereqs)

    issues: list[Issue] = []
    visiting: set[str] = set()
    visited: set[str] = set()

    def visit(node_id: str, stack: list[str]) -> None:
        if node_id in visiting:
            cycle = stack[stack.index(node_id) :] + [node_id] if node_id in stack else stack + [node_id]
            issues.append(Issue(path, f"prerequisites contain a cycle: {' -> '.join(cycle)}"))
            return
        if node_id in visited:
            return

        visiting.add(node_id)
        for dep in graph.get(node_id, []):
            if dep in graph:
                visit(dep, stack + [node_id])
        visiting.remove(node_id)
        visited.add(node_id)

    for node_id in graph:
        visit(node_id, [])

    return issues


def validate_command(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    manifests = find_manifests(root)

    if not manifests:
        print(f"No {MANIFEST_NAME} or {CHECKPOINTS_NAME} files found under {root}", file=sys.stderr)
        return 1

    if len(manifests) == 1 and manifests[0].name == MANIFEST_NAME:
        manifests.extend(referenced_checkpoints_files(manifests[0]))

    all_issues: list[Issue] = []
    total_entries = 0
    global_ids: dict[str, Path] = {}

    for manifest in manifests:
        entry_count, issues = validate_manifest(manifest)
        total_entries += entry_count
        all_issues.extend(issues)

        try:
            data = json.loads(manifest.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            continue

        if not isinstance(data, list):
            continue

        for index, node in enumerate(data):
            if not isinstance(node, dict) or not isinstance(node.get("id"), str):
                continue
            node_id = node["id"]
            other = global_ids.get(node_id)
            if other is not None and other != manifest:
                all_issues.append(Issue(manifest, f"entry[{index}].id: duplicates id from {other}: {node_id!r}"))
            else:
                global_ids[node_id] = manifest

    if all_issues:
        for issue in all_issues:
            print(f"{issue.path}: {issue.message}", file=sys.stderr)
        print(
            f"Validated {len(manifests)} state file(s), {total_entries} item(s), "
            f"{len(all_issues)} issue(s).",
            file=sys.stderr,
        )
        return 1

    if not args.quiet:
        print(f"OK: validated {len(manifests)} state file(s), {total_entries} item(s).")
    return 0


def uuid_command(args: argparse.Namespace) -> int:
    for _ in range(args.count):
        print(generate_id())
    return 0


def transition_command(args: argparse.Namespace) -> int:
    issues = WORKFLOW_STATE_MACHINE.transition_issues(Path("<state-machine>"), "transition", args.current, args.target)
    if issues:
        for issue in issues:
            print(issue.message, file=sys.stderr)
        return 1
    if not args.quiet:
        print(f"OK: {args.current} -> {args.target}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Better Plan manifest utility")
    subparsers = parser.add_subparsers(dest="command", required=True)

    validate = subparsers.add_parser("validate", help=f"validate a workspace {MANIFEST_NAME} and its referenced {CHECKPOINTS_NAME} files")
    validate.add_argument("root", nargs="?", default=".", help="Better Plan workspace root, manifest file, or checkpoints file")
    validate.add_argument("--quiet", action="store_true", help="only print validation errors")
    validate.set_defaults(func=validate_command)

    uuid_parser = subparsers.add_parser("uuid", help="generate task IDs")
    uuid_parser.add_argument("--count", type=int, default=1, help="number of IDs to print")
    uuid_parser.set_defaults(func=uuid_command)

    transition = subparsers.add_parser("transition", help="check whether one workflow status can transition to another")
    transition.add_argument("current", help="current status")
    transition.add_argument("target", help="target status")
    transition.add_argument("--quiet", action="store_true", help="only print transition errors")
    transition.set_defaults(func=transition_command)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    if getattr(args, "count", 1) < 1:
        parser.error("--count must be at least 1")
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
