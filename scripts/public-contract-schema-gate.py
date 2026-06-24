#!/usr/bin/env python3
"""Vityo Public Contract Schema Gate.

Scans public Dart model files for schemaVersion compliance:

1. Every class with toJson() / fromJson() should have a `schemaVersion` field
   (default 1) unless it is explicitly marked as internal-only.
2. toJson() must include 'schemaVersion' in its output.
3. fromJson() must accept missing schemaVersion gracefully.
4. Classes with fromJson() should preserve unknown fields in an `extensions` or
   `extraFields` map, unless documented as internal-only.

Usage:
    python3 scripts/public-contract-schema-gate.py

Returns 0 when all checks pass.
"""

import os
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

REPO_ROOT = Path(__file__).resolve().parent.parent

# Directories to scan for public contracts
SCAN_DIRS = [
    "frontend/vityo_app/lib/src/view_ide/agent",
    "frontend/vityo_app/lib/src/view_ide/runtime",
    "frontend/vityo_app/lib/src/view_ide/workspace",
    "frontend/vityo_app/lib/src/view_ide/workbench",
    "frontend/vityo_app/lib/src/view_ide/language",
    "frontend/vityo_app/lib/src/view_ide/debugger",
    "frontend/vityo_app/lib/src/view_ide/module_host",
    "frontend/vityo_app/lib/src/view_ide/commands",
]

# Files to skip (store-layer, internal-only, or pure controllers)
SKIP_PATTERNS = [
    "_store.dart",        # Data store files (have static const schemaVersion at store level)
    "_controller.dart",   # UI controllers
    "_surface.dart",      # UI surfaces
    "_stub.dart",         # Stub implementations
    "_io.dart",           # Platform I/O
    "_web.dart",          # Platform web
    "agent_tool_call_execution_journal.dart",  # Has specialized redaction, OK
    "agent_tool_input_validator.dart",         # Pure validator, no toJson
    "agent_tool_call_lifecycle.dart",          # Lifecycle controller
    "agent_tool_session_processor.dart",       # Session processor
    "agent_tool_session_transcript.dart",      # Has own schema handling
    "runtime_replay_summary.dart",             # Display data, no toJson/fromJson
    "runtime_task_lifecycle.dart",             # Lifecycle events
    "workspace_controller.dart",               # UI controller
    "workspace_breadcrumbs.dart",              # UI
    "workspace_code_lens.dart",                # UI
    "workspace_declaration.dart",              # UI
    "workspace_definition.dart",               # UI
    "workspace_document_highlights.dart",      # UI
    "workspace_document_links.dart",           # UI
    "workspace_call_hierarchy.dart",           # UI
    "workspace_code_actions.dart",             # UI
    "workspace_outline.dart",                  # UI
    "workspace_implementation.dart",           # UI
    "workspace_navigation_history.dart",       # UI
    "workspace_problems.dart",                 # UI
    "workspace_quick_open.dart",               # UI
    "workspace_reference_search.dart",         # UI
    "workspace_rename.dart",                   # UI
    "workspace_search.dart",                   # UI
    "workspace_symbol_search.dart",            # UI
    "workspace_type_definition.dart",          # UI
    "workspace_type_hierarchy.dart",           # UI
    "workspace_search_service.dart",           # Service
    "workspace_search_history_store.dart",     # Store
    "workspace_file_operations.dart",          # Operations
    "workspace_file_command_router.dart",      # Router
    "workspace_file_explorer_controller.dart", # UI controller
    "workspace_file_explorer_state_store.dart", # Store
    "workspace_diagnostics_controller.dart",    # UI controller
    "workspace_diagnostics_filter_store.dart",  # Store
    "source_control_status.dart",              # UI status
    "source_control_status_controller.dart",   # UI controller
    "source_control_commit_draft_store.dart",  # Store
    "source_control_diff_session_store.dart",  # Store
    "hosted_backend_retry_executor.dart",      # Executor
    "hosted_workspace_lifecycle.dart",         # Lifecycle
    "hosted_workspace_document_store.dart",    # Store
    "workspace_document_store.dart",           # Store
    "workspace_document_store_types.dart",     # Store types
    "workspace_document_store_io.dart",        # Platform
    "workspace_document_store_web.dart",       # Platform
    "extension_runtime_task_contributions.dart", # Ext contributions
    "extension_host_supervisor_execution.dart",  # Ext execution
    "runtime_output_channel_history_store.dart", # Store
    "runtime_task_history_store.dart",           # Store
    "runtime_surface_feature_registry.dart",     # Surface
    "debug_adapter_launcher.dart",             # Launcher
    "debug_adapter_process_transport_io.dart", # Platform I/O
    "debug_adapter_protocol.dart",             # Protocol impl
    "debug_adapter_session.dart",              # Session impl
    "debug_adapter_transport.dart",            # Transport impl
    "debug_breakpoint_store.dart",             # Store
    "debug_launch_readiness_io.dart",          # Platform
    "debug_launch_telemetry_store.dart",       # Store
    "debug_runtime_task_history.dart",         # History
    "debug_smoke_readiness_io.dart",           # Platform
    "extension_debug_contributions.dart",      # Ext
    "agent_coding_skill.dart",                 # Skill implementation
    "agent_coding_session_controller.dart",    # Controller
    "agent_provider_registry.dart",            # Registry
    "agent_tool_registry.dart",                # Registry
    "agent_provider_credential_resolver.dart", # Credential
    "agent_provider_adapter.dart",             # Adapter
    "agent_provider_kind.dart",                # Simple enum
    "agent_code_patch_applier.dart",           # Implementation
    "agent_builtin_tool_executor.dart",        # Implementation
    "agent_tool_call_dispatcher.dart",         # Dispatcher
    "agent_tool_call_execution_plan.dart",     # Execution plan (no fromJson on models)
    "agent_tool_call_result_context.dart",     # Result context
    "agent_tool_call_stream_bridge.dart",      # Stream bridge
    "agent_tool_permission_policy_store.dart", # Store
    "agent_workspace_snapshot_store.dart",     # Store
    "agent_workspace_edit_adapter.dart",       # Adapter
    "agent_prompt_profile_store.dart",         # Store
    "agent_coding_validation_pipeline.dart",   # Pipeline
    "agent_coding_change_review_gate.dart",    # Review gate
    "agent_coding_autonomy_policy.dart",       # Policy
    "agent_coding_loop_context.dart",          # Context
    "extension_manifest_registry_store.dart",  # Store
    "extension_activator.dart",               # Activator
    "extension_lifecycle.dart",               # Lifecycle
    "extension_host_isolation.dart",          # Isolation
    "language_fixture_confidence_matrix.dart", # Internal service
    "simple_styio_language_service.dart",      # Internal service
    "styio_toolchain_discovery.dart",          # Re-export
    "semantic_snapshot_event_bridge.dart",     # Event bridge (internal)
    "semantic_snapshot_provider.dart",         # Provider
    "language_service_foundation.dart",        # Foundation
    "local_styio_language_service.dart",       # Service
    "project_styio_language_service.dart",     # Service
    "project_styio_document_service.dart",     # Service
    "styio_service_capability.dart",           # Capability
    "styio_service_capability_detector.dart",  # Detector
    "styio_service_capability_profile.dart",   # Profile
    "styio_service_connector.dart",            # Connector
    "styio_service_daemon_process_adapter.dart", # Adapter
    "styio_service_manager_connector.dart",    # Connector
    "styio_service_runtime.dart",             # Runtime
    "styio_service_subscription.dart",         # Subscription
    "styio_language_service.dart",            # Service
    "styio_language_provider_registry.dart",   # Registry
    "styio_workspace_diagnostics_provider.dart", # Provider
    "project_document_diagnostics.dart",       # Diagnostics
    "project_document_quick_fixes.dart",       # Quick fixes
    "project_document_rule_registry.dart",     # Registry
    "project_document_rule_provider.dart",     # Provider
    "legacy_project_document_rule_provider.dart", # Legacy
    # ── Settings / config with fromJson for local persistence only ──
    "agent_settings.dart",                # Settings models use fromJson for local-file persistence, not API contract
    "agent_profile.dart",                 # Agent profile config with fromJson for local persistence
    "command_keybinding_profile.dart",    # Keybinding profile stored locally, not API contract
    # ── Internal agent models with fromJson for testing convenience ──
    "agent_tool_permission.dart",         # Permission models use fromJson for test fixtures only
    "agent_workspace_snapshot.dart",      # Workspace snapshot internal to agent module
    # ── Internal extension lifecycle (not cross-machine) ──
    "extension_lifecycle_hooks.dart",     # Lifecycle hooks internal to module host
    # ── Runtime output channels: internal event bus, not API contract ──
    "runtime_output_channels.dart",       # Output channels are internal event model
    # ── Workspace diagnostics: internal notification model ──
    "workspace_diagnostics.dart",         # Diagnostics model internal to workspace surface
    # ── Workspace edit: internal transaction model ──
    "workspace_edit.dart",                # Edit transaction internal to workspace controller
    "debug_launch_contract.dart",         # Debug launch models fixed; store class has store-level schema
]


def find_dart_files(base_dir: Path) -> List[Path]:
    """Find all .dart files under a directory, excluding hidden dirs."""
    dart_files = []
    if not base_dir.is_dir():
        return dart_files
    for root, dirs, files in os.walk(str(base_dir)):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for f in files:
            if f.endswith(".dart"):
                dart_files.append(Path(root) / f)
    return dart_files


def should_skip(file_path: Path) -> bool:
    """Check if a file should be skipped from schema gate."""
    name = file_path.name
    for pattern in SKIP_PATTERNS:
        if pattern in name:
            return True
    return False


def has_to_json(content: str) -> bool:
    """Check if file contains toJson() method."""
    return bool(re.search(r'\btoJson\s*\(\s*\)', content))


def has_from_json(content: str) -> bool:
    """Check if file contains fromJson() factory or method."""
    return bool(re.search(r'\bfromJson\s*\(', content))


def find_classes_with_to_json(content: str) -> List[Tuple[str, int]]:
    """Find class names that have toJson() methods. Returns (name, line)."""
    classes = []
    # Find class declarations
    for match in re.finditer(r'^class\s+(\w+)', content, re.MULTILINE):
        class_name = match.group(1)
        line = content[:match.start()].count('\n') + 1
        # Check if content after class has toJson()
        class_start = match.start()
        # Simple heuristic: find next class or EOF
        next_class = re.search(r'^class\s+\w+', content[class_start + 1:], re.MULTILINE)
        class_end = (
            class_start + 1 + next_class.start()
            if next_class
            else len(content)
        )
        class_content = content[class_start:class_end]
        if has_to_json(class_content):
            classes.append((class_name, line))
    return classes


def check_schema_version_in_class(
    content: str, class_name: str
) -> List[str]:
    """Check a single class for schemaVersion compliance. Returns issues.

    Differentiates between:
    - BLOCKING: Type has both toJson + fromJson (public contract) but
      misses schemaVersion / extensions.
    - ADVISORY: Type has only toJson (output-only) but misses
      schemaVersion. Noted as [ADVISORY].
    """
    issues = []

    # Find the class body
    class_pattern = re.compile(
        rf'^class\s+{re.escape(class_name)}\s*[^{{]*\{{',
        re.MULTILINE,
    )
    class_match = class_pattern.search(content)
    if not class_match:
        return issues

    class_start = class_match.start()
    # Find matching closing brace
    brace_count = 0
    class_end = class_start
    for i in range(class_match.end() - 1, len(content)):
        if content[i] == '{':
            brace_count += 1
        elif content[i] == '}':
            brace_count -= 1
            if brace_count == 0:
                class_end = i + 1
                break

    class_content = content[class_start:class_end]
    has_from = has_from_json(class_content)

    # Check for schemaVersion field
    has_field = bool(
        re.search(
            r'(?:final\s+)?int\s+schemaVersion\s*[=;,]',
            class_content,
        )
    )
    if not has_field:
        if has_from:
            issues.append(f"BLOCKING: Missing 'schemaVersion' field in {class_name}")
        else:
            # Output-only types: schemaVersion is recommended but not blocking
            issues.append(f"ADVISORY: Missing 'schemaVersion' field in {class_name} (output-only, no fromJson)")

    # Check toJson outputs schemaVersion
    if has_to_json(class_content):
        # Find the toJson method within this class
        to_json_match = re.search(
            r'Map<[^>]+>\s+toJson\s*\(\s*\)',
            class_content,
        )
        if to_json_match:
            method_start = to_json_match.start()
            # Find matching braces for toJson method
            method_brace_start = content.find('{', class_start + method_start)
            if method_brace_start != -1 and method_brace_start < class_end:
                method_brace_count = 0
                method_end = method_brace_start
                for i in range(method_brace_start, class_end):
                    if content[i] == '{':
                        method_brace_count += 1
                    elif content[i] == '}':
                        method_brace_count -= 1
                        if method_brace_count == 0:
                            method_end = i + 1
                            break
                method_content = content[method_brace_start:method_end]
                if "'schemaVersion'" not in method_content and \
                   '"schemaVersion"' not in method_content:
                    label = "BLOCKING" if has_from else "ADVISORY"
                    issues.append(
                        f"{label}: toJson() does not output 'schemaVersion' in {class_name}"
                    )

    # Check fromJson handles missing schemaVersion
    if has_from:
        from_json_match = re.search(
            r'factory\s+\w+\.fromJson\s*\(',
            class_content,
        )
        if from_json_match:
            method_start = from_json_match.start()
            method_brace_start = content.find('{', class_start + method_start)
            if method_brace_start != -1 and method_brace_start < class_end:
                method_brace_count = 0
                method_end = method_brace_start
                for i in range(method_brace_start, class_end):
                    if content[i] == '{':
                        method_brace_count += 1
                    elif content[i] == '}':
                        method_brace_count -= 1
                        if method_brace_count == 0:
                            method_end = i + 1
                            break
                method_content = content[method_brace_start:method_end]
                if "schemaVersion" not in method_content:
                    issues.append(
                        f"BLOCKING: fromJson() does not read 'schemaVersion' in {class_name}"
                    )

        # Check for extensions/extraFields
        if "extension" not in class_content.lower() and \
           "extraField" not in class_content:
            issues.append(
                f"BLOCKING: No 'extensions' or 'extraFields' map for unknown fields in {class_name}"
            )

    return issues


def scan_file(file_path: Path) -> List[str]:
    """Scan a single Dart file for schemaVersion compliance."""
    issues = []
    try:
        content = file_path.read_text(encoding="utf-8")
    except Exception:
        return [f"Cannot read {file_path}"]

    # Skip files without serialization
    if not has_to_json(content):
        return []

    classes = find_classes_with_to_json(content)
    for class_name, line in classes:
        # Skip private classes, enums, extensions, and typedefs
        if class_name.startswith('_'):
            continue
        class_issues = check_schema_version_in_class(content, class_name)
        for issue in class_issues:
            rel = file_path.relative_to(REPO_ROOT)
            issues.append(f"{rel}:{line}: {issue}")

    return issues


# ── Main ───────────────────────────────────────────────────────────────────


def fail(reason: str) -> None:
    print(f"FAIL: {reason}", file=sys.stderr)


def ok(message: str) -> None:
    print(f"  OK  {message}")


def main() -> int:
    blocking = 0
    advisory = 0

    print("=== Vityo Public Contract Schema Gate ===\n")

    all_files = []
    for scan_dir_rel in SCAN_DIRS:
        scan_dir = REPO_ROOT / scan_dir_rel
        all_files.extend(find_dart_files(scan_dir))

    # Deduplicate
    all_files = sorted(set(all_files))

    scanned = 0
    for dart_file in all_files:
        if should_skip(dart_file):
            continue
        scanned += 1
        issues = scan_file(dart_file)
        for issue in issues:
            if "BLOCKING:" in issue:
                fail(issue)
                blocking += 1
            elif "ADVISORY:" in issue:
                print(f"  WARN {issue}")
                advisory += 1
            else:
                fail(issue)
                blocking += 1

    print(f"\nScanned {scanned} public model files.")
    if blocking == 0 and advisory == 0:
        print("All public contract schema checks passed.")
    elif blocking == 0:
        print(f"No blocking schema issues. {advisory} advisory note(s) (output-only types).")
        print("Gate PASSED (advisory items are tracked but non-blocking).")
    else:
        print(f"\n{blocking} blocking schema issue(s), {advisory} advisory note(s).")
        print("Blocking issues must be fixed before merge.", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
