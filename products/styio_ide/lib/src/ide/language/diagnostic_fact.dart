import 'dart:collection';

import '../workbench/capability_snapshot.dart';

enum IdeDiagnosticSeverity { error, warning, information }

final class IdeDiagnosticFact {
  IdeDiagnosticFact({
    required this.resourceId,
    required this.severity,
    required this.code,
    required this.message,
    required this.line,
    required this.column,
    required this.length,
    required this.provenance,
  }) {
    if (resourceId.trim().isEmpty ||
        code.trim().isEmpty ||
        message.trim().isEmpty ||
        provenance.trim().isEmpty) {
      throw ArgumentError(
        'Diagnostic resource, code, message, and provenance are required.',
      );
    }
    if (line <= 0 || column <= 0 || length < 0) {
      throw ArgumentError(
        'Diagnostic line/column must be positive and length non-negative.',
      );
    }
  }

  final String resourceId;
  final IdeDiagnosticSeverity severity;
  final String code;
  final String message;
  final int line;
  final int column;
  final int length;
  final String provenance;

  Map<String, Object?> toJson() => <String, Object?>{
    'resourceId': resourceId,
    'severity': severity.name,
    'code': code,
    'message': message,
    'line': line,
    'column': column,
    'length': length,
    'provenance': provenance,
  };

  @override
  bool operator ==(Object other) =>
      other is IdeDiagnosticFact &&
      resourceId == other.resourceId &&
      severity == other.severity &&
      code == other.code &&
      message == other.message &&
      line == other.line &&
      column == other.column &&
      length == other.length &&
      provenance == other.provenance;

  @override
  int get hashCode => Object.hash(
    resourceId,
    severity,
    code,
    message,
    line,
    column,
    length,
    provenance,
  );
}

final class DeveloperDiagnosticBatch {
  DeveloperDiagnosticBatch({
    required this.state,
    required this.provenance,
    required this.message,
    required Iterable<IdeDiagnosticFact> diagnostics,
  }) : diagnostics = UnmodifiableListView(
         List<IdeDiagnosticFact>.of(diagnostics),
       );

  final IdeCapabilityState state;
  final String provenance;
  final String message;
  final List<IdeDiagnosticFact> diagnostics;
}

final class RevisionedDiagnosticFacts {
  RevisionedDiagnosticFacts({
    required this.workspaceRevision,
    required this.state,
    required this.provenance,
    required this.message,
    required Iterable<IdeDiagnosticFact> diagnostics,
  }) : diagnostics = UnmodifiableListView(
         List<IdeDiagnosticFact>.of(diagnostics),
       );

  final int workspaceRevision;
  final IdeCapabilityState state;
  final String provenance;
  final String message;
  final List<IdeDiagnosticFact> diagnostics;

  Map<String, Object?> toJson() => <String, Object?>{
    'workspaceRevision': workspaceRevision,
    'state': state.name,
    'provenance': provenance,
    'message': message,
    'diagnostics': diagnostics
        .map((diagnostic) => diagnostic.toJson())
        .toList(growable: false),
  };

  @override
  bool operator ==(Object other) =>
      other is RevisionedDiagnosticFacts &&
      workspaceRevision == other.workspaceRevision &&
      state == other.state &&
      provenance == other.provenance &&
      message == other.message &&
      _diagnosticListsEqual(diagnostics, other.diagnostics);

  @override
  int get hashCode => Object.hash(
    workspaceRevision,
    state,
    provenance,
    message,
    Object.hashAll(diagnostics),
  );
}

bool _diagnosticListsEqual(
  List<IdeDiagnosticFact> left,
  List<IdeDiagnosticFact> right,
) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
