#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
APP_LIB_ROOT = REPO_ROOT / "products" / "vityo_app" / "lib"
SRC_ROOT = APP_LIB_ROOT / "src"
VIEW_IDE_ROOT = SRC_ROOT / "view_ide"
IDE_ROOT = SRC_ROOT / "ide"
VIEW_RENDER_ROOT = SRC_ROOT / "view_render"

FORBIDDEN_VIEW_IDE_PRESENTATION_IMPORTS = {
    "dart:ui",
    "package:flutter/cupertino.dart",
    "package:flutter/material.dart",
    "package:flutter/rendering.dart",
    "package:flutter/widgets.dart",
}

# Registered public contract/model surfaces that view_render may consume from
# view_ide. New view_render -> view_ide imports must be reviewed by updating
# this list instead of importing arbitrary view_ide implementation modules.
VIEW_RENDER_ALLOWED_VIEW_IDE_IMPORTS = {
    "view_ide/backend_toolchain/adapter_contracts.dart",
    "view_ide/backend_toolchain/dependency_source_adapter.dart",
    "view_ide/backend_toolchain/deployment_adapter.dart",
    "view_ide/backend_toolchain/execution_adapter.dart",
    "view_ide/backend_toolchain/execution_route_summary.dart",
    "view_ide/backend_toolchain/project_graph_contract.dart",
    "view_ide/backend_toolchain/required_handoff_summary.dart",
    "view_ide/backend_toolchain/toolchain_management_adapter.dart",
    "view_ide/commands/commands.dart",
    "view_ide/debugger/debug_adapter_launcher.dart",
    "view_ide/debugger/debug_launch_contract.dart",
    "view_ide/debugger/debug_launch_telemetry_store.dart",
    "ide/editor/controllers/editor_session_facade.dart",    "ide/editor/input/editor_composition.dart",    "ide/editor/input/unicode_boundary_index.dart",    "ide/editor/performance/rendered_input_performance_protocol.dart",    "ide/editor/selection/selection_state.dart",    "ide/local_service/vityod_client.dart",    "ide/editor/document_state.dart",
    "ide/editor/editor_controller.dart",
    "ide/editor/editor_render_layers.dart",
    "ide/editor/render_plan/render_plan.dart",
    "ide/editor/selection_state.dart",
    "view_ide/environment/configuration/configuration.dart",
    "view_ide/environment/configuration/vityo_theme_override.dart",
    "view_ide/environment/environment.dart",
    "view_ide/foundation/foundation.dart",
    "view_ide/interaction/interaction.dart",
    "view_ide/language/language_contract.dart",
    "view_ide/language/semantic_snapshot_panel.dart",
    "view_ide/services/observable_topology/observable_topology.dart",
    "view_ide/module_host/module_definition.dart",
    "view_ide/module_host/module_host.dart",
    "view_ide/module_host/module_manifest.dart",
    "view_ide/platform/platform_target.dart",
    "view_ide/runtime/runtime.dart",
    "view_ide/runtime/runtime_execution_plan.dart",
    "view_ide/runtime/runtime_output_channels.dart",
    "view_ide/runtime/runtime_replay_summary.dart",
    "view_ide/runtime/runtime_surface_feature_registry.dart",
    "view_ide/shell_runtime/shell_runtime.dart",
    "view_ide/testing/testing.dart",
    "view_ide/toolchain/toolchain.dart",
    "view_ide/toolchain/toolchain_catalog.dart",
    "view_ide/toolchain/toolchain_manager.dart",
    "ide/workspace/source_control_commit_draft_store.dart",
    "ide/workspace/source_control_status.dart",
    "ide/workspace/workspace.dart",
}

DIRECTIVE_PATTERN = re.compile(r"^\s*(import|export)\s+['\"]([^'\"]+)['\"]")


@dataclass(frozen=True)
class DartDirective:
    source: Path
    line_number: int
    kind: str
    uri: str
    target: Path | None


def dart_files(root: Path) -> list[Path]:
    if not root.is_dir():
        return []
    return sorted(path for path in root.rglob("*.dart") if not path.name.endswith(".g.dart"))


def relative_to_repo(path: Path) -> str:
    try:
        return path.resolve().relative_to(REPO_ROOT.resolve()).as_posix()
    except ValueError:
        return path.as_posix()


def relative_to_src(path: Path) -> str | None:
    try:
        return path.resolve().relative_to(SRC_ROOT.resolve()).as_posix()
    except ValueError:
        return None


def is_under(path: Path, root: Path) -> bool:
    try:
        path.resolve().relative_to(root.resolve())
    except ValueError:
        return False
    return True


def resolve_dart_uri(uri: str, source: Path) -> Path | None:
    if uri.startswith("dart:"):
        return None
    if uri.startswith("package:vityo_app/"):
        return (APP_LIB_ROOT / uri.removeprefix("package:vityo_app/")).resolve()
    if uri.startswith("package:"):
        return None
    if "://" in uri:
        return None
    return (source.parent / uri).resolve()


def extract_directives(path: Path) -> list[DartDirective]:
    directives: list[DartDirective] = []
    lines = path.read_text(encoding="utf-8").splitlines()
    for line_number, line in enumerate(lines, start=1):
        match = DIRECTIVE_PATTERN.match(line)
        if match is None:
            continue
        kind, uri = match.groups()
        directives.append(
            DartDirective(
                source=path,
                line_number=line_number,
                kind=kind,
                uri=uri,
                target=resolve_dart_uri(uri, path),
            )
        )
    return directives


def iter_directives(root: Path) -> list[DartDirective]:
    directives: list[DartDirective] = []
    for path in dart_files(root):
        directives.extend(extract_directives(path))
    return directives


def format_violation(directive: DartDirective, message: str) -> str:
    location = f"{relative_to_repo(directive.source)}:{directive.line_number}"
    return f"{location}: {message}: {directive.uri}"


def check_view_ide_no_view_render_dependency() -> list[str]:
    errors: list[str] = []
    for root in (VIEW_IDE_ROOT, IDE_ROOT):
        for directive in iter_directives(root):
            if directive.target is not None and is_under(directive.target, VIEW_RENDER_ROOT):
                errors.append(
                    format_violation(
                        directive,
                        "IDE domain must not import or export view_render",
                    )
                )
    return errors


def check_view_ide_no_presentation_api() -> list[str]:
    errors: list[str] = []
    for root in (VIEW_IDE_ROOT, IDE_ROOT):
        for directive in iter_directives(root):
            if directive.uri in FORBIDDEN_VIEW_IDE_PRESENTATION_IMPORTS:
                errors.append(
                    format_violation(
                        directive,
                        "IDE domain must not import Flutter presentation APIs",
                    )
                )
    return errors


def check_view_render_registered_view_ide_contracts() -> list[str]:
    errors: list[str] = []
    for directive in iter_directives(VIEW_RENDER_ROOT):
        if directive.target is None or not (
            is_under(directive.target, VIEW_IDE_ROOT)
            or is_under(directive.target, IDE_ROOT)
        ):
            continue
        target_rel = relative_to_src(directive.target)
        if target_rel not in VIEW_RENDER_ALLOWED_VIEW_IDE_IMPORTS:
            errors.append(
                format_violation(
                    directive,
                    "view_render may only depend on registered view_ide contract surfaces",
                )
            )
    return errors


def check_architecture_boundaries() -> list[str]:
    errors: list[str] = []
    errors.extend(check_view_ide_no_view_render_dependency())
    errors.extend(check_view_ide_no_presentation_api())
    errors.extend(check_view_render_registered_view_ide_contracts())
    return errors


def print_text_report(errors: list[str]) -> int:
    if not errors:
        print("[architecture-boundaries] OK")
        return 0
    print("[architecture-boundaries] FAILED", file=sys.stderr)
    for error in sorted(errors):
        print(f"  - {error}", file=sys.stderr)
    return 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Check Vityo view_ide/view_render architecture boundaries."
    )
    parser.add_argument("--json", action="store_true", help="Emit JSON instead of text.")
    args = parser.parse_args(argv)

    errors = check_architecture_boundaries()
    if args.json:
        print(
            json.dumps(
                {"ok": not errors, "errors": errors},
                indent=2,
                sort_keys=True,
            )
        )
        return 0 if not errors else 1
    return print_text_report(errors)


if __name__ == "__main__":
    raise SystemExit(main())
