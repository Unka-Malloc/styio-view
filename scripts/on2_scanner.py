#!/usr/bin/env python3
"""
O(n^2) Pattern Scanner

Scans Dart source files for potential O(n^2) performance patterns:
1. Nested loops over collections (for-in-for-in)
2. Linear scans in hot paths (indexOf, contains on long strings in loops)
3. Repeated string concatenation in loops
4. Repeated list/set/Map lookups inside loops

Usage:
    python3 scripts/on2_scanner.py [--dir <source-dir>] [--output <output-file>]

Outputs:
    - JSON list of findings
    - Exits with code 1 if patterns exceed threshold
"""

import argparse
import json
import os
import re
import sys
from typing import Any


class ON2Finding:
    """Represents a potential O(n^2) pattern found in source code."""

    def __init__(self, file_path: str, line: int, pattern_type: str,
                 snippet: str, severity: str = "warning"):
        self.file_path = file_path
        self.line = line
        self.pattern_type = pattern_type
        self.snippet = snippet.strip()[:120]
        self.severity = severity

    def to_dict(self) -> dict[str, Any]:
        return {
            "file": self.file_path,
            "line": self.line,
            "pattern_type": self.pattern_type,
            "snippet": self.snippet,
            "severity": self.severity,
        }

    def __repr__(self) -> str:
        return f"[{self.severity}] {self.file_path}:{self.line} - {self.pattern_type}: {self.snippet}"


class ON2Scanner:
    """Scans Dart source files for O(n^2) patterns."""

    # Pattern: nested for-in loops
    RE_NESTED_FOR = re.compile(
        r'for\s*\([^)]*\)\s*\{[^}]*for\s*\('
    )

    # Pattern: string concatenation via += in loops (potential O(n^2))
    RE_STRING_CONCAT = re.compile(
        r'(for|while)\s*\([^)]*\)\s*\{[^}]*\w+\s*\+=\s*["\']'
    )

    # Pattern: indexOf in a loop (linear scan inside loop)
    RE_INDEX_OF_IN_LOOP = re.compile(
        r'(for|while)\s*\([^)]*\)\s*\{[^}]*\.indexOf\('
    )

    # Pattern: contains on a list inside a loop (O(n) per call)
    RE_CONTAINS_IN_LOOP = re.compile(
        r'(for|while)\s*\([^)]*\)\s*\{[^}]*\.contains\('
    )

    # Pattern: List constructor with repeated access in loop
    RE_LIST_GENERATION = re.compile(
        r'List<[^>]*>\s*\.generate\s*\(\s*\w+\s*,\s*\('
    )

    # Pattern: where().toList() chains inside loops
    RE_WHERE_TO_LIST = re.compile(
        r'(for|while)\s*\([^)]*\)\s*\{[^}]*\.where\s*\([^)]*\)\s*\.toList\('
    )

    # Pattern: nested while loops
    RE_NESTED_WHILE = re.compile(
        r'while\s*\([^)]*\)\s*\{[^}]*while\s*\('
    )

    # Pattern: sorting inside a loop
    RE_SORT_IN_LOOP = re.compile(
        r'(for|while)\s*\([^)]*\)\s*\{[^}]*\.sort\s*\('
    )

    # Pattern: sublist in a loop (copying)
    RE_SUBLIST_IN_LOOP = re.compile(
        r'(for|while)\s*\([^)]*\)\s*\{[^}]*\.sublist\s*\('
    )

    def __init__(self, source_dirs: list[str], exclude_patterns: list[str] | None = None):
        self.source_dirs = source_dirs
        self.exclude_patterns = exclude_patterns or [
            r'\.git/',
            r'build/',
            r'\.dart_tool/',
            r'node_modules/',
            r'__pycache__',
            r'\.pub-cache',
        ]
        self.findings: list[ON2Finding] = []

    def _should_exclude(self, path: str) -> bool:
        for pattern in self.exclude_patterns:
            if re.search(pattern, path):
                return True
        return False

    def _scan_file(self, file_path: str) -> None:
        """Scan a single Dart file for O(n^2) patterns."""
        try:
            with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
                content = f.read()
        except Exception as e:
            print(f"  Warning: Could not read {file_path}: {e}", file=sys.stderr)
            return

        lines = content.split("\n")

        # Check each pattern
        checks = [
            ("nested_for_loop", self.RE_NESTED_FOR, "warning"),
            ("string_concat_in_loop", self.RE_STRING_CONCAT, "warning"),
            ("indexOf_in_loop", self.RE_INDEX_OF_IN_LOOP, "warning"),
            ("contains_in_loop", self.RE_CONTAINS_IN_LOOP, "warning"),
            ("where_toList_in_loop", self.RE_WHERE_TO_LIST, "warning"),
            ("nested_while_loop", self.RE_NESTED_WHILE, "warning"),
            ("sort_in_loop", self.RE_SORT_IN_LOOP, "info"),
            ("sublist_in_loop", self.RE_SUBLIST_IN_LOOP, "info"),
        ]

        for pattern_name, regex, severity in checks:
            for match in regex.finditer(content):
                # Find the line number
                line_num = content[:match.start()].count("\n") + 1

                # Get the context (the matching line)
                if line_num <= len(lines):
                    snippet = lines[line_num - 1]
                else:
                    snippet = match.group()[:120]

                self.findings.append(ON2Finding(
                    file_path=file_path,
                    line=line_num,
                    pattern_type=pattern_name,
                    snippet=snippet,
                    severity=severity,
                ))

        # Check for List.generate patterns that might be O(n^2)
        for match in self.RE_LIST_GENERATION.finditer(content):
            line_num = content[:match.start()].count("\n") + 1
            snippet = lines[line_num - 1] if line_num <= len(lines) else match.group()[:120]
            self.findings.append(ON2Finding(
                file_path=file_path,
                line=line_num,
                pattern_type="list_generate",
                snippet=snippet,
                severity="info",
            ))

    def scan(self) -> list[ON2Finding]:
        """Scan all source directories for O(n^2) patterns."""
        print(f"Scanning for O(n²) patterns in {len(self.source_dirs)} directories...")

        dart_files = []
        for src_dir in self.source_dirs:
            if os.path.isfile(src_dir) and src_dir.endswith(".dart"):
                dart_files.append(src_dir)
            elif os.path.isdir(src_dir):
                for root, dirs, files in os.walk(src_dir):
                    dirs[:] = [d for d in dirs if not self._should_exclude(os.path.join(root, d))]
                    for f in files:
                        if f.endswith(".dart"):
                            file_path = os.path.join(root, f)
                            if not self._should_exclude(file_path):
                                dart_files.append(file_path)

        print(f"  Found {len(dart_files)} Dart files to scan")

        for file_path in dart_files:
            self._scan_file(file_path)

        # Sort findings by severity
        severity_order = {"high": 0, "warning": 1, "info": 2}
        self.findings.sort(key=lambda f: (severity_order.get(f.severity, 3), f.file_path, f.line))

        return self.findings

    def summary(self) -> dict[str, Any]:
        """Generate summary of findings."""
        by_severity: dict[str, int] = {}
        by_type: dict[str, int] = {}
        for finding in self.findings:
            by_severity[finding.severity] = by_severity.get(finding.severity, 0) + 1
            by_type[finding.pattern_type] = by_type.get(finding.pattern_type, 0) + 1

        return {
            "total_findings": len(self.findings),
            "by_severity": by_severity,
            "by_pattern": by_type,
            "findings": [f.to_dict() for f in self.findings],
        }


def main():
    parser = argparse.ArgumentParser(description="O(n^2) Pattern Scanner for Vityo")
    parser.add_argument(
        "--dir", "-d",
        action="append",
        help="Source directory to scan (can be specified multiple times)",
    )
    parser.add_argument(
        "--output", "-o",
        help="Output JSON file for findings",
    )
    parser.add_argument(
        "--threshold",
        type=int,
        default=50,
        help="Fail if findings exceed this threshold (default: 50)",
    )
    parser.add_argument(
        "--fail-on-warning",
        action="store_true",
        help="Fail if any warning-level findings are present",
    )

    args = parser.parse_args()

    # Default directories
    source_dirs = args.dir or [
        os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                     "frontend", "vityo_app", "lib"),
    ]

    scanner = ON2Scanner(source_dirs)
    findings = scanner.scan()
    summary = scanner.summary()

    print(f"\nO(n²) Pattern Scan Summary:")
    print(f"  Total findings: {summary['total_findings']}")
    for severity, count in summary["by_severity"].items():
        print(f"    {severity}: {count}")
    print()

    for finding in findings:
        print(f"  {finding}")

    if args.output:
        output_path = args.output
        with open(output_path, "w") as f:
            json.dump(summary, f, indent=2)
        print(f"\nResults written to {output_path}")

    # Determine exit code
    exit_code = 0
    if summary["total_findings"] > args.threshold:
        print(f"\nFAIL: {summary['total_findings']} findings exceed threshold of {args.threshold}")
        exit_code = 1
    if args.fail_on_warning and summary["by_severity"].get("warning", 0) > 0:
        print(f"\nFAIL: {summary['by_severity']['warning']} warning-level findings")
        exit_code = 1

    sys.exit(exit_code)


if __name__ == "__main__":
    main()
