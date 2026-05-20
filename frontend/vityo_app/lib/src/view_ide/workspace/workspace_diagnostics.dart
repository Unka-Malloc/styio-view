import '../foundation/foundation.dart';
import '../editor/document_state.dart';
import '../language/language_contract.dart';
import 'workspace_edit.dart';

class WorkspaceDiagnosticsRequest {
  const WorkspaceDiagnosticsRequest({
    required this.documentIds,
    this.activeDocumentId = '',
    this.documents = const <DocumentState>[],
  });

  final List<String> documentIds;
  final String activeDocumentId;
  final List<DocumentState> documents;
}

class WorkspaceDiagnostic {
  const WorkspaceDiagnostic({
    required this.documentId,
    required this.diagnostic,
    this.providerId = '',
    this.source = 'language',
  });

  final String documentId;
  final Diagnostic diagnostic;
  final String providerId;
  final String source;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'documentId': documentId,
      if (providerId.isNotEmpty) 'providerId': providerId,
      'source': source,
      'severity': diagnostic.severity.name,
      'code': diagnostic.code,
      'message': diagnostic.message,
      'range': <String, int>{
        'start': diagnostic.range.start,
        'end': diagnostic.range.end,
      },
    };
  }
}

class WorkspaceDiagnosticsDocumentGroup {
  const WorkspaceDiagnosticsDocumentGroup({
    required this.documentId,
    required this.diagnostics,
  });

  final String documentId;
  final List<WorkspaceDiagnostic> diagnostics;

  bool get hasErrors {
    return diagnostics.any(
      (entry) => entry.diagnostic.severity == DiagnosticSeverity.error,
    );
  }

  int get totalCount => diagnostics.length;

  Map<String, int> get severityCounts {
    return <String, int>{
      for (final severity in DiagnosticSeverity.values)
        severity.name: diagnostics
            .where((entry) => entry.diagnostic.severity == severity)
            .length,
    };
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'documentId': documentId,
      'totalCount': totalCount,
      'severityCounts': severityCounts,
      'hasErrors': hasErrors,
    };
  }
}

class WorkspaceDiagnosticsSourceGroup {
  const WorkspaceDiagnosticsSourceGroup({
    required this.source,
    required this.diagnostics,
  });

  final String source;
  final List<WorkspaceDiagnostic> diagnostics;

  bool get hasErrors {
    return diagnostics.any(
      (entry) => entry.diagnostic.severity == DiagnosticSeverity.error,
    );
  }

  int get totalCount => diagnostics.length;

  Map<String, int> get severityCounts {
    return <String, int>{
      for (final severity in DiagnosticSeverity.values)
        severity.name: diagnostics
            .where((entry) => entry.diagnostic.severity == severity)
            .length,
    };
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'source': source,
      'totalCount': totalCount,
      'severityCounts': severityCounts,
      'hasErrors': hasErrors,
    };
  }
}

class WorkspaceDiagnosticsSnapshot {
  const WorkspaceDiagnosticsSnapshot({
    required this.providerId,
    required this.diagnostics,
    this.message = '',
  });

  final String providerId;
  final List<WorkspaceDiagnostic> diagnostics;
  final String message;

  bool get hasErrors {
    return diagnostics.any(
      (entry) => entry.diagnostic.severity == DiagnosticSeverity.error,
    );
  }

  int get totalCount => diagnostics.length;

  Map<String, int> get severityCounts {
    return <String, int>{
      for (final severity in DiagnosticSeverity.values)
        severity.name: diagnostics
            .where((entry) => entry.diagnostic.severity == severity)
            .length,
    };
  }

  List<String> get documentIds {
    final ids = diagnostics.map((entry) => entry.documentId).toSet().toList();
    ids.sort();
    return ids;
  }

  List<WorkspaceDiagnosticsDocumentGroup> get documentGroups {
    final groups = <String, List<WorkspaceDiagnostic>>{};
    for (final diagnostic in diagnostics) {
      groups.putIfAbsent(diagnostic.documentId, () => <WorkspaceDiagnostic>[]);
      groups[diagnostic.documentId]!.add(diagnostic);
    }
    final result = groups.entries
        .map(
          (entry) => WorkspaceDiagnosticsDocumentGroup(
            documentId: entry.key,
            diagnostics: List<WorkspaceDiagnostic>.unmodifiable(entry.value),
          ),
        )
        .toList(growable: false);
    result.sort((left, right) {
      final byErrors = right.hasErrors.toString().compareTo(
        left.hasErrors.toString(),
      );
      if (byErrors != 0) {
        return byErrors;
      }
      return left.documentId.compareTo(right.documentId);
    });
    return List<WorkspaceDiagnosticsDocumentGroup>.unmodifiable(result);
  }

  List<WorkspaceDiagnosticsSourceGroup> get sourceGroups {
    return groupWorkspaceDiagnosticsBySource(diagnostics);
  }

  List<WorkspaceDiagnostic> diagnosticsFor(String documentId) {
    return diagnostics
        .where((entry) => entry.documentId == documentId)
        .toList(growable: false);
  }

  List<WorkspaceDiagnostic> diagnosticsForSeverity(
    DiagnosticSeverity severity,
  ) {
    return diagnostics
        .where((entry) => entry.diagnostic.severity == severity)
        .toList(growable: false);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'providerId': providerId,
      'totalCount': totalCount,
      'documentIds': documentIds,
      'documentGroups': documentGroups
          .map((group) => group.toJson())
          .toList(growable: false),
      'sourceGroups': sourceGroups
          .map((group) => group.toJson())
          .toList(growable: false),
      'severityCounts': severityCounts,
      'hasErrors': hasErrors,
      if (message.isNotEmpty) 'message': message,
      'diagnostics': diagnostics
          .map((diagnostic) => diagnostic.toJson())
          .toList(growable: false),
    };
  }
}

class WorkspaceDiagnosticsFilterState {
  const WorkspaceDiagnosticsFilterState({
    this.severities = const <DiagnosticSeverity>[],
    this.documentQuery = '',
    this.sources = const <String>[],
  });

  final List<DiagnosticSeverity> severities;
  final String documentQuery;
  final List<String> sources;

  bool get active {
    return severities.isNotEmpty ||
        documentQuery.trim().isNotEmpty ||
        sources.isNotEmpty;
  }

  String get summary {
    final parts = <String>[
      if (severities.isNotEmpty)
        severities.map((severity) => severity.name).join(','),
      if (documentQuery.trim().isNotEmpty) 'document ${documentQuery.trim()}',
      if (sources.isNotEmpty) 'source ${sources.join(',')}',
    ];
    return parts.join(' · ');
  }

  bool matches(WorkspaceDiagnostic diagnostic) {
    if (severities.isNotEmpty &&
        !severities.contains(diagnostic.diagnostic.severity)) {
      return false;
    }
    final normalizedDocumentQuery = documentQuery.trim().toLowerCase();
    if (normalizedDocumentQuery.isNotEmpty &&
        !diagnostic.documentId.toLowerCase().contains(
          normalizedDocumentQuery,
        )) {
      return false;
    }
    if (sources.isNotEmpty && !sources.contains(diagnostic.source)) {
      return false;
    }
    return true;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'severities': severities.map((severity) => severity.name).toList(),
      if (documentQuery.trim().isNotEmpty)
        'documentQuery': documentQuery.trim(),
      if (sources.isNotEmpty) 'sources': sources,
      'active': active,
      if (summary.isNotEmpty) 'summary': summary,
    };
  }

  factory WorkspaceDiagnosticsFilterState.fromJson(Map<String, Object?> json) {
    final severities = json['severities'];
    final sources = json['sources'];
    return WorkspaceDiagnosticsFilterState(
      severities: severities is List
          ? severities
                .map((severity) => _diagnosticSeverityFromName('$severity'))
                .whereType<DiagnosticSeverity>()
                .toList(growable: false)
          : const <DiagnosticSeverity>[],
      documentQuery: json['documentQuery'] as String? ?? '',
      sources: sources is List
          ? sources.map((source) => '$source').toList(growable: false)
          : const <String>[],
    );
  }
}

class WorkspaceDiagnosticsView {
  const WorkspaceDiagnosticsView({
    required this.providerId,
    required this.filter,
    required this.diagnostics,
    required this.visibleDiagnostics,
  });

  final String providerId;
  final WorkspaceDiagnosticsFilterState filter;
  final List<WorkspaceDiagnostic> diagnostics;
  final List<WorkspaceDiagnostic> visibleDiagnostics;

  factory WorkspaceDiagnosticsView.fromSnapshot(
    WorkspaceDiagnosticsSnapshot snapshot, {
    WorkspaceDiagnosticsFilterState filter =
        const WorkspaceDiagnosticsFilterState(),
  }) {
    return WorkspaceDiagnosticsView.fromDiagnostics(
      providerId: snapshot.providerId,
      diagnostics: snapshot.diagnostics,
      filter: filter,
    );
  }

  factory WorkspaceDiagnosticsView.fromDiagnostics({
    required String providerId,
    required List<WorkspaceDiagnostic> diagnostics,
    WorkspaceDiagnosticsFilterState filter =
        const WorkspaceDiagnosticsFilterState(),
  }) {
    return WorkspaceDiagnosticsView(
      providerId: providerId,
      filter: filter,
      diagnostics: List<WorkspaceDiagnostic>.unmodifiable(diagnostics),
      visibleDiagnostics: List<WorkspaceDiagnostic>.unmodifiable(
        diagnostics.where(filter.matches),
      ),
    );
  }

  int get totalCount => diagnostics.length;
  int get visibleCount => visibleDiagnostics.length;

  Map<String, int> get severityCounts {
    return <String, int>{
      for (final severity in DiagnosticSeverity.values)
        severity.name: diagnostics
            .where((entry) => entry.diagnostic.severity == severity)
            .length,
    };
  }

  List<WorkspaceDiagnosticsDocumentGroup> get documentGroups {
    return groupWorkspaceDiagnostics(visibleDiagnostics);
  }

  List<WorkspaceDiagnosticsSourceGroup> get sourceGroups {
    return groupWorkspaceDiagnosticsBySource(visibleDiagnostics);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'providerId': providerId,
      'filter': filter.toJson(),
      'totalCount': totalCount,
      'visibleCount': visibleCount,
      'severityCounts': severityCounts,
      'documentGroups': documentGroups
          .map((group) => group.toJson())
          .toList(growable: false),
      'sourceGroups': sourceGroups
          .map((group) => group.toJson())
          .toList(growable: false),
      'diagnostics': visibleDiagnostics
          .map((diagnostic) => diagnostic.toJson())
          .toList(growable: false),
    };
  }
}

enum WorkspaceQuickFixConfirmationStatus {
  ready,
  blockedMissingDocuments,
  blockedNoPreview,
}

extension WorkspaceQuickFixConfirmationStatusX
    on WorkspaceQuickFixConfirmationStatus {
  String get wireValue => switch (this) {
    WorkspaceQuickFixConfirmationStatus.ready => 'ready',
    WorkspaceQuickFixConfirmationStatus.blockedMissingDocuments =>
      'blocked-missing-documents',
    WorkspaceQuickFixConfirmationStatus.blockedNoPreview =>
      'blocked-no-preview',
  };
}

class WorkspaceQuickFixConfirmationPlan {
  const WorkspaceQuickFixConfirmationPlan({
    required this.planId,
    required this.status,
    required this.message,
    this.summary = '',
    this.affectedDocumentIds = const <String>[],
    this.missingDocumentIds = const <String>[],
    this.todo = '',
  });

  factory WorkspaceQuickFixConfirmationPlan.fromPreview(
    WorkspaceEditPreview? preview,
  ) {
    if (preview == null) {
      return const WorkspaceQuickFixConfirmationPlan(
        planId: '',
        status: WorkspaceQuickFixConfirmationStatus.blockedNoPreview,
        message: 'Workspace quick fix has no preview to confirm.',
      );
    }
    if (preview.missingDocumentIds.isNotEmpty) {
      return WorkspaceQuickFixConfirmationPlan(
        planId: preview.planId,
        status: WorkspaceQuickFixConfirmationStatus.blockedMissingDocuments,
        summary: preview.summary,
        affectedDocumentIds: _sortedStrings(
          preview.documents.map((document) => document.documentId),
        ),
        missingDocumentIds: _sortedStrings(preview.missingDocumentIds),
        message:
            'Workspace quick fix is blocked until missing documents are loaded.',
      );
    }
    return WorkspaceQuickFixConfirmationPlan(
      planId: preview.planId,
      status: WorkspaceQuickFixConfirmationStatus.ready,
      summary: preview.summary,
      affectedDocumentIds: _sortedStrings(
        preview.documents.map((document) => document.documentId),
      ),
      message: 'Workspace quick fix is ready for user confirmation.',
      todo:
          'TODO: bind this confirmation plan to a diff preview and explicit apply confirmation UI.',
    );
  }

  final String planId;
  final WorkspaceQuickFixConfirmationStatus status;
  final String message;
  final String summary;
  final List<String> affectedDocumentIds;
  final List<String> missingDocumentIds;
  final String todo;

  bool get ready => status == WorkspaceQuickFixConfirmationStatus.ready;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'planId': planId,
      'status': status.wireValue,
      'ready': ready,
      'message': message,
      if (summary.isNotEmpty) 'summary': summary,
      'affectedDocumentIds': affectedDocumentIds,
      'missingDocumentIds': missingDocumentIds,
      if (todo.isNotEmpty) 'todo': todo,
    };
  }
}

List<WorkspaceDiagnosticsDocumentGroup> groupWorkspaceDiagnostics(
  List<WorkspaceDiagnostic> diagnostics,
) {
  final groups = <String, List<WorkspaceDiagnostic>>{};
  for (final diagnostic in diagnostics) {
    groups.putIfAbsent(diagnostic.documentId, () => <WorkspaceDiagnostic>[]);
    groups[diagnostic.documentId]!.add(diagnostic);
  }
  final result = groups.entries
      .map(
        (entry) => WorkspaceDiagnosticsDocumentGroup(
          documentId: entry.key,
          diagnostics: List<WorkspaceDiagnostic>.unmodifiable(entry.value),
        ),
      )
      .toList(growable: false);
  result.sort((left, right) {
    if (left.hasErrors != right.hasErrors) {
      return left.hasErrors ? -1 : 1;
    }
    return left.documentId.compareTo(right.documentId);
  });
  return List<WorkspaceDiagnosticsDocumentGroup>.unmodifiable(result);
}

List<WorkspaceDiagnosticsSourceGroup> groupWorkspaceDiagnosticsBySource(
  List<WorkspaceDiagnostic> diagnostics,
) {
  final groups = <String, List<WorkspaceDiagnostic>>{};
  for (final diagnostic in diagnostics) {
    groups.putIfAbsent(diagnostic.source, () => <WorkspaceDiagnostic>[]);
    groups[diagnostic.source]!.add(diagnostic);
  }
  final result = groups.entries
      .map(
        (entry) => WorkspaceDiagnosticsSourceGroup(
          source: entry.key,
          diagnostics: List<WorkspaceDiagnostic>.unmodifiable(entry.value),
        ),
      )
      .toList(growable: false);
  result.sort((left, right) {
    if (left.hasErrors != right.hasErrors) {
      return left.hasErrors ? -1 : 1;
    }
    return left.source.compareTo(right.source);
  });
  return List<WorkspaceDiagnosticsSourceGroup>.unmodifiable(result);
}

List<String> _sortedStrings(Iterable<String> values) {
  final result =
      values
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList(growable: false)
        ..sort();
  return result;
}

DiagnosticSeverity? _diagnosticSeverityFromName(String value) {
  for (final severity in DiagnosticSeverity.values) {
    if (severity.name == value) {
      return severity;
    }
  }
  return null;
}

abstract class WorkspaceDiagnosticsProvider {
  const WorkspaceDiagnosticsProvider();

  String get providerId;

  Future<WorkspaceDiagnosticsSnapshot> collect(
    WorkspaceDiagnosticsRequest request,
  );
}

class StaticWorkspaceDiagnosticsProvider
    implements WorkspaceDiagnosticsProvider {
  const StaticWorkspaceDiagnosticsProvider({
    required this.providerId,
    required this.snapshot,
  });

  @override
  final String providerId;
  final WorkspaceDiagnosticsSnapshot snapshot;

  @override
  Future<WorkspaceDiagnosticsSnapshot> collect(
    WorkspaceDiagnosticsRequest request,
  ) async {
    return snapshot;
  }
}

class WorkspaceDiagnosticsProviderRegistration {
  const WorkspaceDiagnosticsProviderRegistration({
    required this.id,
    required this.provider,
    this.priority = 0,
    this.state = FoundationRegistryEntryState.registered,
    this.metadata = const <String, Object?>{},
    this.todo = '',
  });

  final String id;
  final WorkspaceDiagnosticsProvider provider;
  final int priority;
  final FoundationRegistryEntryState state;
  final Map<String, Object?> metadata;
  final String todo;
}

class WorkspaceDiagnosticsProviderRegistry {
  WorkspaceDiagnosticsProviderRegistry({
    FoundationProviderRegistry<WorkspaceDiagnosticsProvider>? registry,
  }) : _registry =
           registry ??
           FoundationProviderRegistry<WorkspaceDiagnosticsProvider>();

  static const String owner = 'workspace.diagnostics';
  static const String collectCapability = 'workspace.diagnostics.collect';

  final FoundationProviderRegistry<WorkspaceDiagnosticsProvider> _registry;

  void register(WorkspaceDiagnosticsProviderRegistration registration) {
    _registry.register(
      FoundationProviderRegistration<WorkspaceDiagnosticsProvider>(
        id: registration.id,
        owner: owner,
        provider: registration.provider,
        layer: 'workspace',
        priority: registration.priority,
        state: registration.state,
        capabilities: const <String>[collectCapability],
        metadata: <String, Object?>{
          ...registration.metadata,
          'providerContract': 'workspace-diagnostics-provider',
        },
        todo: registration.todo,
      ),
    );
  }

  FoundationRegistryEntry<WorkspaceDiagnosticsProvider>? resolve({
    bool activeOnly = true,
  }) {
    return _registry.resolve(
      capability: collectCapability,
      owner: owner,
      activeOnly: activeOnly,
    );
  }

  WorkspaceDiagnosticsProvider? provider({bool activeOnly = true}) {
    return resolve(activeOnly: activeOnly)?.value;
  }

  FoundationRegistryManifest manifest({FoundationRegistryEntryState? state}) {
    return _registry.manifest(owner: owner, state: state);
  }
}
