import '../foundation/foundation.dart';
import '../editor/document_state.dart';
import '../language/language_contract.dart';

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
      'severityCounts': severityCounts,
      'hasErrors': hasErrors,
      if (message.isNotEmpty) 'message': message,
      'diagnostics': diagnostics
          .map((diagnostic) => diagnostic.toJson())
          .toList(growable: false),
    };
  }
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
